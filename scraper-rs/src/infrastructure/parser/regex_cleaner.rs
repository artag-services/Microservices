use regex::Regex;
use crate::domain::ports::ContentCleanerPort;

const NOISE_TAGS: &[&str] = &["script", "style", "nav", "footer", "header", "aside", "noscript"];

pub struct RegexCleaner;

impl ContentCleanerPort for RegexCleaner {
    fn clean(&self, html: &str) -> String {
        let mut result = html.to_string();
        for tag in NOISE_TAGS {
            let re = Regex::new(&format!(r"(?is)<{}[^>]*>.*?</{}>", tag, tag)).unwrap();
            result = re.replace_all(&result, "").to_string();
        }
        let re = Regex::new(r"(?is)<!--.*?-->").unwrap();
        re.replace_all(&result, "").to_string()
    }
}
