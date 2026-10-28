fn main() {
    println!("cargo:rerun-if-changed=build.rs");
    if std::env::var("CARGO_CFG_TARGET_OS").as_deref() == Ok("macos") {
        // Dart rewrites bundled dylib install names to the runtime asset path.
        println!("cargo:rustc-link-arg-cdylib=-Wl,-headerpad_max_install_names");
    }
}
