/// URL normalization for httpCheck (DT-PRV-16 / INV-D-PRV-17).
pub fn normalize(raw: &str) -> Option<String> {
    let t = raw.trim();
    if t.is_empty() {
        return None;
    }
    let with_scheme = if t.contains("://") {
        t.to_string()
    } else if t.contains(' ') {
        return None;
    } else {
        format!("http://{t}")
    };
    if with_scheme.starts_with("http://") || with_scheme.starts_with("https://") {
        Some(with_scheme)
    } else {
        None
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn dt_prv_url_localhost() {
        assert_eq!(
            normalize("localhost:3000/").as_deref(),
            Some("http://localhost:3000/")
        );
    }

    #[test]
    fn dt_prv_url_spaces_invalid() {
        assert!(normalize("a b.com").is_none());
    }
}
