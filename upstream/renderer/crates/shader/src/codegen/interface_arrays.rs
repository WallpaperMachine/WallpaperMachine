//! Shared bounds for generated stage-interface arrays and their locations.

use crate::{
    ShaderError, ShaderResult,
    syntax::{ShaderModule, SyntaxItem},
};

/// Resolves a positive literal or a leading object-like macro to one array size.
/// Unsupported expressions and late definitions must not silently reserve one
/// location while emission allocates a larger array.
pub(crate) fn interface_array_size(module: &ShaderModule<'_>, suffix: &str) -> ShaderResult<u32> {
    let bound = suffix
        .strip_prefix('[')
        .and_then(|value| value.strip_suffix(']'))
        .map(str::trim)
        .unwrap_or_default();
    let positive_integer = |value: &str| {
        let value = value.trim();
        (!value.is_empty() && value.bytes().all(|byte| byte.is_ascii_digit()))
            .then(|| value.parse::<u32>().ok())
            .flatten()
            .filter(|size| *size > 0)
    };
    if let Some(size) = positive_integer(bound) {
        return Ok(size);
    }
    let mut replacement = None;
    for item in module.items() {
        let SyntaxItem::Directive(directive) = item else {
            break;
        };
        if directive.name_text() == "undef" && directive.body_text() == bound {
            replacement = None;
        } else if let Some(parts) = directive
            .define_parts()
            .map_err(ShaderError::invalid_request)?
        {
            if parts.name_text() == bound {
                replacement = parts.object_like_name_text()
                    .and_then(|_| parts.simple_replacement_text());
            }
        }
    }
    replacement.and_then(positive_integer).ok_or_else(|| ShaderError::invalid_request(format!(
        "unsupported stage-interface array bound `{suffix}`: expected a positive integer or a leading macro with a positive integer value"
    )))
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::ShaderStageKind;

    #[test]
    fn interface_bounds_follow_leading_macro_undefinitions_and_redefinitions() {
        for (directives, expected) in [
            ("#define COUNT 2\n", Some(2)),
            ("#define COUNT 2\n#define COUNT 3\n", Some(3)),
            ("#define COUNT 2\n#undef COUNT\n", None),
            ("#define COUNT 2\n#undef COUNT\n#define COUNT 3\n", Some(3)),
            ("#define COUNT 2\n#define COUNT(x) x\n", None),
            ("#define COUNT 2\n#define COUNT\n", Some(1)), // bare defines have implicit value 1
        ] {
            let source = format!("{directives}varying vec2 taps[COUNT];\n");
            let module = ShaderModule::parse(ShaderStageKind::Fragment, &source).unwrap();
            assert_eq!(interface_array_size(&module, "[COUNT]").ok(), expected, "{directives}");
        }
    }
}
