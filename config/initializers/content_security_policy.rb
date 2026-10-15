Rails.application.configure do
  config.content_security_policy do |policy|
    policy.default_src :self
    policy.script_src  :self
    policy.style_src   :self, "https://cdn.jsdelivr.net", "https://fonts.googleapis.com"
    policy.font_src    :self, "https://fonts.gstatic.com"
    image_sources = [ :self, "https://covers.openlibrary.org", "https://s3-hz6esvk2smrtw7u55epupn5p.rocio.ornelas.io" ]
    image_sources.push("http://localhost:4566") if Rails.env.development?

    policy.img_src(*image_sources)
    policy.object_src :none
  end
  config.content_security_policy_nonce_generator = ->(request) { request.session.id.to_s }
  config.content_security_policy_nonce_directives = [ "style-src" ]
end
