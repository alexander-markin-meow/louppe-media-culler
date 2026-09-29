cask "louppe" do
  version "1.9.0"
  sha256 "27fccb1520a50b049535a0e9a72534bdc426b7a7907d24a4ef3cb37053e59361"

  url "https://github.com/murlexander/louppe-media-culler/releases/download/v#{version}/Louppe.zip",
      verified: "github.com/murlexander/louppe-media-culler/"
  name "Louppe"
  desc "Keyboard-first media culler"
  homepage "https://louppe.eu/"

  livecheck do
    url :url
    strategy :github_latest
  end

  auto_updates true
  depends_on arch: :arm64
  depends_on macos: :sonoma

  app "Louppe.app"
end
