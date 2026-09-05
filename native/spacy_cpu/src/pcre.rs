use std::ffi::c_void;

extern "C" {
    fn pcre2_compile_8(
        pattern: *const u8,
        length: usize,
        options: u32,
        error: *mut i32,
        offset: *mut usize,
        context: *mut c_void,
    ) -> *mut c_void;
    fn pcre2_code_free_8(code: *mut c_void);
    fn pcre2_match_data_create_from_pattern_8(
        code: *const c_void,
        context: *mut c_void,
    ) -> *mut c_void;
    fn pcre2_match_data_free_8(data: *mut c_void);
    fn pcre2_match_8(
        code: *const c_void,
        subject: *const u8,
        length: usize,
        start: usize,
        options: u32,
        data: *mut c_void,
        context: *mut c_void,
    ) -> i32;
    fn pcre2_get_ovector_pointer_8(data: *mut c_void) -> *mut usize;
    fn pcre2_jit_compile_8(code: *mut c_void, options: u32) -> i32;
}

pub struct Regex {
    code: *mut c_void,
    data: *mut c_void,
}
impl Regex {
    pub fn new(pattern: &str) -> Result<Self, String> {
        let pattern = pattern.strip_prefix("(?u)").unwrap_or(pattern);
        // Python's \uHHHH and \UHHHHHHHH escapes use PCRE2's \x{...} spelling.
        let mut converted = String::new();
        let mut chars = pattern.chars();
        while let Some(c) = chars.next() {
            if c == '\\' {
                let escaped = chars.next().ok_or("trailing regex escape")?;
                if escaped == 'u' || escaped == 'U' {
                    let digits: String = chars
                        .by_ref()
                        .take(if escaped == 'u' { 4 } else { 8 })
                        .collect();
                    if !digits.chars().all(|d| d.is_ascii_hexdigit()) {
                        return Err("invalid Unicode regex escape".into());
                    }
                    converted.push_str(&format!("\\x{{{digits}}}"));
                } else {
                    converted.push(c);
                    converted.push(escaped);
                }
            } else {
                converted.push(c);
            }
        }
        let pattern = converted.as_str();
        let mut error = 0;
        let mut offset = 0;
        let code = unsafe {
            pcre2_compile_8(
                pattern.as_ptr(),
                pattern.len(),
                0x000a0000,
                &mut error,
                &mut offset,
                std::ptr::null_mut(),
            )
        };
        if code.is_null() {
            return Err(format!("regex compilation error {error} at {offset}"));
        }
        let data = unsafe { pcre2_match_data_create_from_pattern_8(code, std::ptr::null_mut()) };
        if data.is_null() {
            unsafe {
                pcre2_code_free_8(code);
            }
            return Err("regex allocation failed".into());
        }
        unsafe {
            pcre2_jit_compile_8(code, 1);
        }
        Ok(Self { code, data })
    }
    pub fn find(&self, text: &str, start: usize) -> Result<Option<(usize, usize)>, String> {
        let found = unsafe {
            pcre2_match_8(
                self.code,
                text.as_ptr(),
                text.len(),
                start,
                0,
                self.data,
                std::ptr::null_mut(),
            )
        };
        if found == -1 {
            return Ok(None);
        }
        if found < 0 {
            return Err(format!("regex execution error {found}"));
        }
        let positions = unsafe { pcre2_get_ovector_pointer_8(self.data) };
        let pair = unsafe { (*positions, *positions.add(1)) };
        if !text.is_char_boundary(pair.0) || !text.is_char_boundary(pair.1) {
            return Err("regex returned non-UTF-8 boundary".into());
        }
        Ok(Some(pair))
    }
}
impl Drop for Regex {
    fn drop(&mut self) {
        unsafe {
            pcre2_match_data_free_8(self.data);
            pcre2_code_free_8(self.code);
        }
    }
}
