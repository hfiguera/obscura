use crate::{
    hash,
    tokenizer::{Token, Tokenizer},
};
use memmap2::Mmap;
use serde::Deserialize;
use serde_json::{json, Value};
use std::{
    collections::HashMap,
    fs::{self, File},
    path::Path,
};

extern "C" {
    fn cblas_sgemm(
        order: i32,
        trans_a: i32,
        trans_b: i32,
        m: i32,
        n: i32,
        k: i32,
        alpha: f32,
        a: *const f32,
        lda: i32,
        b: *const f32,
        ldb: i32,
        beta: f32,
        c: *mut f32,
        ldc: i32,
    );
}

fn gemm(x: &[f32], w: &[f32], rows: usize, input: usize, output: usize) -> Vec<f32> {
    assert_eq!(x.len(), rows * input);
    assert_eq!(w.len(), output * input);
    let mut y = vec![0.0; rows * output];
    if rows > 0 {
        // Fixed, validated row-major f32 arrays. CBLAS does not retain pointers.
        unsafe {
            cblas_sgemm(
                101,
                111,
                112,
                rows as i32,
                output as i32,
                input as i32,
                1.0,
                x.as_ptr(),
                input as i32,
                w.as_ptr(),
                input as i32,
                0.0,
                y.as_mut_ptr(),
                output as i32,
            );
        }
    }
    y
}

#[derive(Deserialize)]
struct Tensor {
    offset: usize,
    shape: Vec<usize>,
}
pub struct Model {
    pub tokenizer: Tokenizer,
    tensors: HashMap<String, Tensor>,
    weights: Vec<f32>,
    vectors: Mmap,
    keys: HashMap<u64, usize>,
    actions: Vec<String>,
    seeds: Vec<u64>,
}

impl Model {
    pub fn load(path: &Path) -> Result<Self, String> {
        let config: Value =
            serde_json::from_slice(&fs::read(path.join("model.json")).map_err(|e| e.to_string())?)
                .map_err(|e| e.to_string())?;
        if config["schema_version"] != 1
            || config["model"] != "en_core_web_lg"
            || config["version"] != "3.8.0"
        {
            return Err("unsupported model schema".into());
        }
        let raw = fs::read(path.join("weights.bin")).map_err(|e| e.to_string())?;
        if raw.len() % 4 != 0 {
            return Err("invalid weight bytes".into());
        }
        let weights: Vec<f32> = raw
            .chunks_exact(4)
            .map(|v| f32::from_le_bytes(v.try_into().unwrap()))
            .collect();
        let tensors: HashMap<String, Tensor> =
            serde_json::from_value(config["tensors"].clone()).map_err(|e| e.to_string())?;
        for tensor in tensors.values() {
            let end = tensor
                .shape
                .iter()
                .try_fold(1usize, |n, d| n.checked_mul(*d))
                .and_then(|n| n.checked_add(tensor.offset));
            if end.is_none_or(|e| e > weights.len()) {
                return Err("invalid tensor range".into());
            }
        }
        let file = File::open(path.join("vectors.bin")).map_err(|e| e.to_string())?;
        // Assets are read-only for the lifetime of the process.
        let vectors = unsafe { Mmap::map(&file) }.map_err(|e| e.to_string())?;
        if vectors.len() != 342918 * 300 * 4 {
            return Err("unexpected vector table".into());
        }
        let rawkeys = fs::read(path.join("vector_keys.bin")).map_err(|e| e.to_string())?;
        if rawkeys.len() % 12 != 0 {
            return Err("invalid vector keys".into());
        }
        let mut keys = HashMap::with_capacity(rawkeys.len() / 12);
        for record in rawkeys.chunks_exact(12) {
            let key = u64::from_le_bytes(record[..8].try_into().unwrap());
            let row = u32::from_le_bytes(record[8..].try_into().unwrap()) as usize;
            if row >= 342918 {
                return Err("invalid vector row".into());
            }
            keys.insert(key, row);
        }
        let model = Self {
            tokenizer: Tokenizer::load(
                &config,
                fs::read(path.join("unicode.bin")).map_err(|e| e.to_string())?,
            )?,
            tensors,
            weights,
            vectors,
            keys,
            actions: serde_json::from_value(config["actions"].clone())
                .map_err(|e| e.to_string())?,
            seeds: serde_json::from_value(config["hash_seeds"].clone())
                .map_err(|e| e.to_string())?,
        };
        let mut expected = vec![
            ("lower.W".to_string(), vec![3, 64, 2, 64]),
            ("lower.b".into(), vec![64, 2]),
            ("lower.pad".into(), vec![1, 3, 64, 2]),
            ("upper.W".into(), vec![74, 64]),
            ("upper.b".into(), vec![74]),
            ("token.W".into(), vec![64, 96]),
            ("token.b".into(), vec![64]),
            ("static.W".into(), vec![96, 300]),
            ("embed.W".into(), vec![96, 3, 480]),
            ("embed.b".into(), vec![96, 3]),
            ("embed_norm.G".into(), vec![96]),
            ("embed_norm.b".into(), vec![96]),
        ];
        for (h, rows) in [5000, 1000, 2500, 2500].iter().enumerate() {
            expected.push((format!("hash{h}.E"), vec![*rows, 96]));
            expected.push((format!("cnn{h}.W"), vec![96, 3, 288]));
            expected.push((format!("cnn{h}.b"), vec![96, 3]));
            expected.push((format!("cnn{h}_norm.G"), vec![96]));
            expected.push((format!("cnn{h}_norm.b"), vec![96]));
        }
        for (name, shape) in expected {
            if model.tensors.get(&name).is_none_or(|t| t.shape != shape) {
                return Err(format!("unsupported tensor {name}"));
            }
        }
        if model.actions.len() != 74
            || model.seeds.len() != 4
            || !config["unseen_classes"]
                .as_array()
                .is_some_and(|a| a.is_empty())
        {
            return Err("unsupported action or hash configuration".into());
        }
        Ok(model)
    }
    fn w(&self, name: &str) -> &[f32] {
        let t = &self.tensors[name];
        &self.weights[t.offset..t.offset + t.shape.iter().product::<usize>()]
    }
    fn maxout(&self, x: &[f32], rows: usize, input: usize, name: &str) -> Vec<f32> {
        let mut y = gemm(x, self.w(&format!("{name}.W")), rows, input, 288);
        let bias = self.w(&format!("{name}.b"));
        for (i, v) in y.iter_mut().enumerate() {
            *v += bias[i % 288];
        }
        let mut out: Vec<f32> = y
            .chunks_exact(3)
            .map(|p| p[0].max(p[1]).max(p[2]))
            .collect();
        let gain = self.w(&format!("{name}_norm.G"));
        let bias = self.w(&format!("{name}_norm.b"));
        for row in out.chunks_exact_mut(96) {
            let mean = row.iter().sum::<f32>() / 96.0;
            let variance = row.iter().map(|v| (v - mean) * (v - mean)).sum::<f32>() / 96.0 + 1e-8;
            let inv = variance.sqrt().recip();
            for i in 0..96 {
                row[i] = (row[i] - mean) * inv * gain[i] + bias[i];
            }
        }
        out
    }
    fn embed(&self, text: &str, tokens: &[Token], features: &[[u64; 4]]) -> Vec<f32> {
        let n = tokens.len();
        let mut x = vec![0.0; n * 480];
        let mut static_input = vec![0.0; n * 300];
        for (i, token) in tokens.iter().enumerate() {
            for h in 0..4 {
                let name = format!("hash{h}.E");
                let table = self.w(&name);
                let rows = table.len() / 96;
                for bucket in hash::buckets(features[i][h], self.seeds[h], rows) {
                    for j in 0..96 {
                        x[i * 480 + h * 96 + j] += table[bucket * 96 + j];
                    }
                }
            }
            let key = self.tokenizer.hash(&text[token.start..token.end]);
            if let Some(row) = self.keys.get(&key) {
                // Mmap starts on a page boundary and its validated length is a
                // whole f32 table. All supported targets are little-endian.
                let source = unsafe {
                    std::slice::from_raw_parts(
                        self.vectors.as_ptr().add(row * 1200).cast::<f32>(),
                        300,
                    )
                };
                static_input[i * 300..(i + 1) * 300].copy_from_slice(source);
            }
        }
        let projected = gemm(&static_input, self.w("static.W"), n, 300, 96);
        for i in 0..n {
            x[i * 480 + 384..(i + 1) * 480].copy_from_slice(&projected[i * 96..(i + 1) * 96]);
        }
        self.maxout(&x, n, 480, "embed")
    }
    fn encode(&self, embedding: &[f32], n: usize) -> Vec<f32> {
        // spaCy pads four tokens on BOTH sides before all four residual layers.
        // Padding activations are updated too; padding afresh per layer differs.
        let rows = n + 8;
        let mut x = vec![0.0; rows * 96];
        x[4 * 96..(n + 4) * 96].copy_from_slice(embedding);
        for depth in 0..4 {
            let mut window = vec![0.0; rows * 288];
            for i in 0..rows {
                for (p, offset) in [-1isize, 0, 1].iter().enumerate() {
                    let src = i as isize + offset;
                    if src >= 0 && src < rows as isize {
                        window[i * 288 + p * 96..i * 288 + (p + 1) * 96]
                            .copy_from_slice(&x[src as usize * 96..(src as usize + 1) * 96]);
                    }
                }
            }
            let y = self.maxout(&window, rows, 288, &format!("cnn{depth}"));
            for (a, b) in x.iter_mut().zip(y) {
                *a += b;
            }
        }
        x[4 * 96..(n + 4) * 96].to_vec()
    }
    pub fn predict(&self, text: &str, debug: bool, tokens_only: bool) -> Result<Value, String> {
        if text.len() > 1_048_576 {
            return Err("prototype input byte limit exceeded".into());
        }
        let start = std::time::Instant::now();
        let tokens = self.tokenizer.tokenize(text)?;
        if tokens.len() > 10000 {
            return Err("prototype token limit exceeded".into());
        }
        let features: Vec<_> = tokens
            .iter()
            .map(|t| self.tokenizer.features(text, t))
            .collect();
        let token_ms = start.elapsed().as_secs_f64() * 1000.0;
        let debug_tokens: Vec<_> = tokens
            .iter()
            .zip(&features)
            .map(|(t, f)| json!({"start":t.start,"end":t.end,"features":f}))
            .collect();
        if tokens_only {
            return Ok(json!({"tokens":debug_tokens,"tokenization_ms":token_ms}));
        }
        let n = tokens.len();
        let embedding = self.embed(text, &tokens, &features);
        let encoded = self.encode(&embedding, n);
        let mut tokvec = gemm(&encoded, self.w("token.W"), n, 96, 64);
        for (i, v) in tokvec.iter_mut().enumerate() {
            *v += self.w("token.b")[i % 64];
        }
        let lower = gemm(&tokvec, self.w("lower.W"), n, 64, 384);
        let encode_ms = start.elapsed().as_secs_f64() * 1000.0 - token_ms;
        let mut open: Option<(usize, &str)> = None;
        let mut spans = Vec::new();
        let mut trace = Vec::new();
        for i in 0..n {
            let ids = [Some(i), open.map(|(t, _)| t), open.map(|_| i - 1)];
            let mut hidden = vec![0.0f32; 128];
            for (f, token) in ids.iter().enumerate() {
                let source = match token {
                    Some(t) => &lower[t * 384 + f * 128..t * 384 + (f + 1) * 128],
                    None => &self.w("lower.pad")[f * 128..(f + 1) * 128],
                };
                for j in 0..128 {
                    hidden[j] += source[j];
                }
            }
            for (value, bias) in hidden.iter_mut().zip(self.w("lower.b")) {
                *value += bias;
            }
            let h: Vec<f32> = hidden.chunks_exact(2).map(|v| v[0].max(v[1])).collect();
            let mut scores = gemm(&h, self.w("upper.W"), 1, 64, 74);
            for (value, bias) in scores.iter_mut().zip(self.w("upper.b")) {
                *value += bias;
            }
            let space = self
                .tokenizer
                .is_space(&text[tokens[i].start..tokens[i].end]);
            let mut best = None;
            for (j, action) in self.actions.iter().enumerate() {
                let (kind, label) = action.split_once('-').unwrap_or(("O", ""));
                let valid = match kind {
                    "B" => open.is_none() && i + 1 < n && !space && !label.is_empty(),
                    "I" => open.is_some_and(|(_, l)| l == label) && i + 1 < n,
                    "L" => open.is_some_and(|(_, l)| l == label),
                    "U" => open.is_none() && !space && !label.is_empty(),
                    "O" => open.is_none(),
                    _ => false,
                };
                if valid && best.is_none_or(|k| scores[j] > scores[k]) {
                    best = Some(j);
                }
            }
            let j = best.ok_or("no valid transition")?;
            let action = &self.actions[j];
            let (kind, label) = action.split_once('-').unwrap_or(("O", ""));
            if debug {
                trace.push(json!({"action":j,"scores":scores}));
            }
            match kind {
                "B"=>open=Some((i,label)),
                "L"=>{let (begin,label)=open.take().unwrap();spans.push(json!({"label":label,"byte_start":tokens[begin].start,"byte_end":tokens[i].end,"score":0.85}));},
                "U"=>spans.push(json!({"label":label,"byte_start":tokens[i].start,"byte_end":tokens[i].end,"score":0.85})), _=>{}}
        }
        let total = start.elapsed().as_secs_f64() * 1000.0;
        let mut result = json!({"predictions":spans,"token_count":n,"native_ms":total,
            "tokenization_ms":token_ms,"encoding_ms":encode_ms,"decoding_ms":total-token_ms-encode_ms});
        if debug {
            result["tokens"] = json!(debug_tokens);
            result["embedding"] = json!(embedding);
            result["encoded"] = json!(encoded);
            result["token_vectors"] = json!(tokvec);
            result["trace"] = json!(trace);
        }
        Ok(result)
    }
}
