#[test]
pub fn case_unwind_returns_crash_error() {
    let error = crate::owe::unwind::testing::panic_across_c_unwind_for_testing()
        .expect_err("unwind should become EngineError::Crash");

    assert!(
        matches!(error, crate::EngineError::Crash(message) if message.contains("test ffi unwind"))
    );
}

#[test]
pub fn case_ffi_declarations_use_c_unwind_abi() {
    let manifest_dir = std::path::Path::new(env!("CARGO_MANIFEST_DIR"));
    let source = [
        manifest_dir.join("src/owe/unwind.rs"),
        manifest_dir.join("src/owe/backend.rs"),
        manifest_dir.join("build.rs"),
    ]
    .into_iter()
    .map(|path| std::fs::read_to_string(path).expect("OWE bridge source should be readable"))
    .collect::<Vec<_>>()
    .join("\n");
    let bindings = std::fs::read_to_string(concat!(env!("OUT_DIR"), "/owe_backend_bindings.rs"))
        .expect("generated OWE bindings should be readable");

    assert!(source.contains("bindgen::Abi::CUnwind"));
    assert!(bindings.contains("extern \"C-unwind\""));
    assert!(!source.contains("unsafe extern \"C\""));
    assert!(!bindings.contains("unsafe extern \"C\""));
}

#[test]
pub fn case_no_duplicate_owe_runtime_descriptors() {
    let manifest_dir = std::path::Path::new(env!("CARGO_MANIFEST_DIR"));
    let workspace_root = manifest_dir
        .parent()
        .and_then(std::path::Path::parent)
        .expect("wallpaper-core should live under crates/");
    let roots = [
        manifest_dir.join("build.rs"),
        manifest_dir.join("src/engine.rs"),
        manifest_dir.join("src/owe"),
        workspace_root.join("external/open-wallpaper-engine/src/Platform/Apple"),
    ];
    let forbidden = [
        "RawDisplayDesc",
        "RawSceneDesc",
        "RawSceneResult",
        "OweSceneRequest",
        "RuntimeManager",
        "owe_backend_scene_desc",
        "owe_scene_desc",
        "owe_scene_result",
    ];

    let mut files = Vec::new();
    for root in &roots {
        collect_source_files(root, &mut files);
    }
    for path in &files {
        let source = std::fs::read_to_string(path).expect("source file should be readable");
        for pattern in forbidden {
            assert!(
                !source.contains(pattern),
                "{} must not contain duplicate runtime descriptor pattern `{pattern}`",
                path.display()
            );
        }
    }
}

fn collect_source_files(path: &std::path::Path, files: &mut Vec<std::path::PathBuf>) {
    if path.is_file() {
        files.push(path.to_path_buf());
        return;
    }

    let Ok(entries) = std::fs::read_dir(path) else {
        return;
    };
    for entry in entries.flatten() {
        let path = entry.path();
        if path.is_dir() {
            collect_source_files(&path, files);
        } else if matches!(
            path.extension().and_then(|value| value.to_str()),
            Some("rs" | "h" | "hpp" | "mm" | "cpp")
        ) {
            files.push(path);
        }
    }
}
