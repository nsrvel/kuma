use chrono::{DateTime, Utc};

pub fn format_wire_timestamp(dt: DateTime<Utc>) -> String {
    dt.format("%Y-%m-%dT%H:%M:%S%.3fZ").to_string()
}

pub fn now_wire_timestamp() -> String {
    format_wire_timestamp(Utc::now())
}

pub fn parse_wire_timestamp(s: &str) -> Option<DateTime<Utc>> {
    DateTime::parse_from_rfc3339(s)
        .ok()
        .map(|dt| dt.with_timezone(&Utc))
}
