import Foundation

/// Port numbers for UI — always plain decimal (e.g. `8080`, `9200`), never locale grouping (`9.200`).
public enum KumaPortFormatting {
    public static func plain(_ port: Int) -> String {
        String(port)
    }
}
