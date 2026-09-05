// spaCy string hashes (MurmurHash64A) and Thinc's four embedding buckets.
// MurmurHash algorithms by Austin Appleby are public domain.
pub fn string_hash(bytes: &[u8]) -> u64 {
    let m = 0xc6a4a7935bd1e995u64;
    let mut h = 1u64 ^ (bytes.len() as u64).wrapping_mul(m);
    for chunk in bytes.chunks_exact(8) {
        let mut k = u64::from_le_bytes(chunk.try_into().unwrap());
        k = k.wrapping_mul(m);
        k ^= k >> 47;
        k = k.wrapping_mul(m);
        h ^= k;
        h = h.wrapping_mul(m);
    }
    let tail = bytes.chunks_exact(8).remainder();
    for (i, b) in tail.iter().enumerate() {
        h ^= (*b as u64) << (8 * i);
    }
    if !tail.is_empty() {
        h = h.wrapping_mul(m);
    }
    h ^= h >> 47;
    h = h.wrapping_mul(m);
    h ^ (h >> 47)
}

fn fmix(mut h: u64) -> u64 {
    h ^= h >> 33;
    h = h.wrapping_mul(0xff51afd7ed558ccd);
    h ^= h >> 33;
    h = h.wrapping_mul(0xc4ceb9fe1a85ec53);
    h ^ (h >> 33)
}

pub fn buckets(value: u64, seed: u64, rows: usize) -> [usize; 4] {
    let mut h1 = value
        .wrapping_mul(0x87c37b91114253d5)
        .rotate_left(31)
        .wrapping_mul(0x4cf5ad432745937f)
        ^ seed
        ^ 8;
    let mut h2 = seed ^ 8;
    h1 = h1.wrapping_add(h2);
    h2 = h2.wrapping_add(h1);
    h1 = fmix(h1);
    h2 = fmix(h2);
    h1 = h1.wrapping_add(h2);
    h2 = h2.wrapping_add(h1);
    [h1 as u32, (h1 >> 32) as u32, h2 as u32, (h2 >> 32) as u32].map(|v| v as usize % rows)
}
