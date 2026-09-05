mod hash;
mod model;
mod pcre;
mod tokenizer;
use serde_json::{json, Value};
use std::{
    io::{self, BufRead, Read, Write},
    path::Path,
};

#[cfg(target_os = "macos")]
const BACKEND: &str = "rust_accelerate_cpu";
#[cfg(target_os = "linux")]
const BACKEND: &str = "rust_openblas_cpu";

fn peak_rss() -> i64 {
    let mut usage = std::mem::MaybeUninit::<libc::rusage>::uninit();
    if unsafe { libc::getrusage(libc::RUSAGE_SELF, usage.as_mut_ptr()) } == 0 {
        let rss = unsafe { usage.assume_init().ru_maxrss };
        // getrusage reports bytes on macOS, KiB on Linux. Protocol always uses bytes.
        #[cfg(target_os = "linux")]
        let rss = rss.saturating_mul(1024);
        rss
    } else {
        0
    }
}

fn main() -> Result<(), Box<dyn std::error::Error>> {
    let args: Vec<_> = std::env::args().collect();
    if args.len() != 2 {
        return Err("usage: obscura-spacy-native-prototype ASSET_DIRECTORY".into());
    }
    let start = std::time::Instant::now();
    let model = model::Model::load(Path::new(&args[1]))?;
    let mut stdout = io::BufWriter::new(io::stdout().lock());
    writeln!(
        stdout,
        "{}",
        json!({"ready":true,"protocol_version":1,"model":"en_core_web_lg","model_version":"3.8.0","backend":BACKEND,"python_runtime":false,
        "load_ms":start.elapsed().as_secs_f64()*1000.0,"pid":std::process::id(),"peak_rss_bytes":peak_rss()})
    )?;
    stdout.flush()?;
    let mut input = io::BufReader::new(io::stdin().lock());
    let mut line = String::new();
    loop {
        line.clear();
        // Bound the JSON frame before allocating/decoding untrusted input.
        // A 1 MiB text can use up to six JSON bytes per escaped character.
        if input.by_ref().take(8_388_609).read_line(&mut line)? == 0 {
            break;
        }
        if line.len() > 8_388_608 {
            return Err("request frame limit exceeded".into());
        }
        let request: Result<Value, _> = serde_json::from_str(&line);
        let response = match request {
            Ok(request) => match request["text"].as_str() {
                Some(text) => model.predict(
                    text,
                    request["debug"].as_bool().unwrap_or(false),
                    request["tokens_only"].as_bool().unwrap_or(false),
                ),
                None => Err("request requires a text string".into()),
            },
            Err(_) => Err("invalid JSON request".into()),
        };
        let mut response = response.unwrap_or_else(|error| json!({"error":error}));
        response["peak_rss_bytes"] = json!(peak_rss());
        writeln!(stdout, "{response}")?;
        stdout.flush()?;
    }
    Ok(())
}
