fn main() {
    let os = std::env::var("CARGO_CFG_TARGET_OS").unwrap();
    let arch = std::env::var("CARGO_CFG_TARGET_ARCH").unwrap();
    let env = std::env::var("CARGO_CFG_TARGET_ENV").unwrap();
    match (os.as_str(), arch.as_str(), env.as_str()) {
        ("macos", "aarch64", _) => {
            println!("cargo:rustc-link-search=native=/opt/homebrew/lib");
            println!("cargo:rustc-link-lib=framework=Accelerate");
        }
        ("linux", "aarch64" | "x86_64", "gnu") => {
            // Use the LP64 CBLAS ABI (32-bit dimension arguments), not OpenBLAS64.
            println!("cargo:rustc-link-lib=openblas");
        }
        _ => panic!("spaCy CPU supports Apple Silicon macOS and glibc Linux on aarch64/x86_64."),
    }
    println!("cargo:rustc-link-lib=pcre2-8");
}
