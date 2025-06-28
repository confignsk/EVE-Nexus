import Foundation

enum EVEConfig {
    // OAuth 认证相关配置
    enum OAuth {
        static let clientId = "7339147833b44ad3815c7ef0957950c2"
        
        // 从 clientSecret.json 文件读取客户端密钥
        static let clientSecret: String = {
            guard let url = Bundle.main.url(forResource: "clientSecret", withExtension: "json"),
                  let data = try? Data(contentsOf: url),
                  let json = try? JSONSerialization.jsonObject(with: data, options: []) as? [String: Any],
                  let secret = json["secret"] as? String else {
                Logger.warning("[EVEConfig]警告：无法从 clientSecret.json 读取客户端密钥，使用默认值")
                return "NA"
            }
            
            // 打印客户端密钥的前后2个字符
            Logger.info("[EVEConfig]成功读取客户端密钥: \(String(secret.prefix(2)))...\(String(secret.suffix(2)))")
            
            return secret
        }()
        
        static let redirectURI = URL(string: "eveauthpanel://callback/")!

        // API 端点
        static let authorizationEndpoint = URL(
            string: "https://login.eveonline.com/v2/oauth/authorize/")!
        static let tokenEndpoint = URL(string: "https://login.eveonline.com/v2/oauth/token")!

        // JWKS元数据端点（用于验证JWT token）
        static let jwksMetadataEndpoint = URL(
            string: "https://login.eveonline.com/.well-known/oauth-authorization-server")!

        // 基础URL
        static let baseURL = URL(string: "https://login.eveonline.com")!
    }
}
