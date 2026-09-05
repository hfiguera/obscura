use crate::{hash, pcre::Regex};
use serde::Deserialize;
use serde_json::Value;
use std::collections::HashMap;

#[derive(Clone, Deserialize)]
struct Part {
    orth: String,
    norm: Option<String>,
}
#[derive(Clone, Deserialize)]
struct Special {
    word: String,
    tokens: Vec<String>,
}
#[derive(Clone)]
pub struct Token {
    pub start: usize,
    pub end: usize,
    norm: Option<String>,
}

pub struct Tokenizer {
    prefix: Regex,
    suffix: Regex,
    infix: Regex,
    url: Option<Regex>,
    token_match: Option<Regex>,
    rules: HashMap<String, Vec<Part>>,
    special: HashMap<String, Vec<Special>>,
    symbols: HashMap<String, u64>,
    norms: HashMap<u64, String>,
    base_norms: HashMap<String, String>,
    unicode: Vec<u8>,
}

impl Tokenizer {
    pub fn load(config: &Value, unicode: Vec<u8>) -> Result<Self, String> {
        if unicode.len() != 0x110000 {
            return Err("invalid Unicode asset".into());
        }
        let regex = &config["regex"];
        let optional = |key: &str| regex[key].as_str().map(Regex::new).transpose();
        let patterns: Vec<Special> = serde_json::from_value(config["special_patterns"].clone())
            .map_err(|e| e.to_string())?;
        let mut special: HashMap<String, Vec<Special>> = HashMap::new();
        for pattern in patterns {
            special
                .entry(pattern.tokens[0].clone())
                .or_default()
                .push(pattern);
        }
        Ok(Self {
            prefix: Regex::new(regex["prefix_search"].as_str().ok_or("prefix absent")?)?,
            suffix: Regex::new(regex["suffix_search"].as_str().ok_or("suffix absent")?)?,
            infix: Regex::new(regex["infix_finditer"].as_str().ok_or("infix absent")?)?,
            url: optional("url_match")?,
            token_match: optional("token_match")?,
            rules: serde_json::from_value(config["rules"].clone()).map_err(|e| e.to_string())?,
            special,
            symbols: serde_json::from_value(config["symbols"].clone())
                .map_err(|e| e.to_string())?,
            norms: serde_json::from_value(config["norms"].clone()).map_err(|e| e.to_string())?,
            base_norms: serde_json::from_value(config["base_norms"].clone())
                .map_err(|e| e.to_string())?,
            unicode,
        })
    }
    pub fn hash(&self, word: &str) -> u64 {
        if word.is_empty() {
            0
        } else {
            self.symbols
                .get(word)
                .copied()
                .unwrap_or_else(|| hash::string_hash(word.as_bytes()))
        }
    }
    pub fn is_space(&self, text: &str) -> bool {
        !text.is_empty() && text.chars().all(|c| self.unicode[c as usize] & 8 != 0)
    }
    pub fn features(&self, text: &str, token: &Token) -> [u64; 4] {
        let word = &text[token.start..token.end];
        let norm = token
            .norm
            .clone()
            .or_else(|| self.norms.get(&self.hash(word)).cloned())
            .or_else(|| self.base_norms.get(word).cloned())
            .unwrap_or_else(|| word.to_lowercase());
        let chars: Vec<char> = word.chars().collect();
        let shape = if chars.len() >= 100 {
            "LONG".into()
        } else {
            let mut shape = String::new();
            let mut last = None;
            let mut count = 0;
            for c in &chars {
                let flag = self.unicode[*c as usize];
                let s = if flag & 1 != 0 {
                    if flag & 2 != 0 {
                        'X'
                    } else {
                        'x'
                    }
                } else if flag & 4 != 0 {
                    'd'
                } else {
                    *c
                };
                if Some(s) == last {
                    count += 1;
                } else {
                    last = Some(s);
                    count = 0;
                }
                if count < 4 {
                    shape.push(s);
                }
            }
            shape
        };
        let prefix: String = chars.iter().take(1).collect();
        let suffix: String = chars.iter().skip(chars.len().saturating_sub(3)).collect();
        [
            self.hash(&norm),
            self.hash(&prefix),
            self.hash(&suffix),
            self.hash(&shape),
        ]
    }
    fn push(out: &mut Vec<Token>, start: usize, end: usize) {
        if start < end {
            out.push(Token {
                start,
                end,
                norm: None,
            });
        }
    }
    fn apply_rule(&self, word: &str, start: usize, out: &mut Vec<Token>) -> bool {
        if let Some(parts) = self.rules.get(word) {
            let mut pos = start;
            for part in parts {
                out.push(Token {
                    start: pos,
                    end: pos + part.orth.len(),
                    norm: part.norm.clone(),
                });
                pos += part.orth.len();
            }
            true
        } else {
            false
        }
    }
    fn matched(regex: &Option<Regex>, word: &str) -> Result<bool, String> {
        Ok(match regex {
            Some(r) => r.find(word, 0)?.is_some_and(|(s, _)| s == 0),
            None => false,
        })
    }
    fn split(
        &self,
        text: &str,
        mut start: usize,
        mut end: usize,
        out: &mut Vec<Token>,
    ) -> Result<(), String> {
        let mut suffixes = Vec::new();
        while start < end {
            let word = &text[start..end];
            if self.rules.contains_key(word) || Self::matched(&self.token_match, word)? {
                break;
            }
            let pre = self.prefix.find(word, 0)?.map_or(0, |(a, b)| b - a);
            if pre > 0 && start + pre < end && self.rules.contains_key(&text[start + pre..end]) {
                Self::push(out, start, start + pre);
                start += pre;
                break;
            }
            let suf = self.suffix.find(&word[pre..], 0)?.map_or(0, |(a, b)| b - a);
            if suf > 0 && start < end - suf && self.rules.contains_key(&text[start..end - suf]) {
                suffixes.push((end - suf, end));
                end -= suf;
                break;
            }
            if pre == 0 && suf == 0 {
                break;
            }
            if pre > 0 {
                Self::push(out, start, start + pre);
                start += pre;
            }
            if suf > 0 {
                suffixes.push((end - suf, end));
                end -= suf;
            }
        }
        if start < end {
            let word = &text[start..end];
            if !self.apply_rule(word, start, out) {
                if Self::matched(&self.token_match, word)? || Self::matched(&self.url, word)? {
                    Self::push(out, start, end);
                } else {
                    let mut cursor = 0;
                    let mut last = 0;
                    while cursor <= word.len() {
                        let Some((a, b)) = self.infix.find(word, cursor)? else {
                            break;
                        };
                        if a != 0 {
                            Self::push(out, start + last, start + a);
                            Self::push(out, start + a, start + b);
                            last = b;
                        }
                        cursor = if b > a {
                            b
                        } else if b < word.len() {
                            b + word[b..].chars().next().unwrap().len_utf8()
                        } else {
                            break;
                        };
                    }
                    Self::push(out, start + last, end);
                }
            }
        }
        for (a, b) in suffixes.into_iter().rev() {
            Self::push(out, a, b);
        }
        Ok(())
    }
    pub fn tokenize(&self, text: &str) -> Result<Vec<Token>, String> {
        let mut out = Vec::new();
        let mut start = 0;
        let mut in_ws = None;
        for (i, c) in text.char_indices() {
            let ws = self.unicode[c as usize] & 8 != 0;
            if in_ws.is_some_and(|old| old != ws) {
                if start < i {
                    self.split(text, start, i, &mut out)?;
                }
                start = if ws && c == ' ' { i + 1 } else { i };
            }
            in_ws = Some(ws);
        }
        if start < text.len() {
            self.split(text, start, text.len(), &mut out)?;
        }
        // Equivalent to the special-case matcher's longest-token-span-first pass.
        let mut matches = Vec::new();
        for i in 0..out.len() {
            if let Some(patterns) = self.special.get(&text[out[i].start..out[i].end]) {
                for p in patterns {
                    let end = i + p.tokens.len();
                    if end <= out.len()
                        && p.tokens
                            .iter()
                            .zip(&out[i..end])
                            .all(|(word, t)| word == &text[t.start..t.end])
                        && text[out[i].start..out[end - 1].end] == p.word
                    {
                        matches.push((i, end, p.word.as_str()));
                    }
                }
            }
        }
        matches.sort_by_key(|(a, b, _)| (std::cmp::Reverse(b - a), *a));
        let mut used = vec![false; out.len()];
        let mut selected = HashMap::new();
        for (a, b, word) in matches {
            if used[a..b].iter().all(|u| !*u) {
                used[a..b].fill(true);
                selected.insert(a, (b, word));
            }
        }
        let mut final_tokens = Vec::new();
        let mut i = 0;
        while i < out.len() {
            if let Some((end, word)) = selected.get(&i) {
                self.apply_rule(word, out[i].start, &mut final_tokens);
                i = *end;
            } else {
                final_tokens.push(out[i].clone());
                i += 1;
            }
        }
        Ok(final_tokens)
    }
}
