cask "volumegrid" do
  version "1.0.0"
  sha256 "PLACEHOLDER_SHA256_HASH"

  url "https://github.com/euxx/VolumeGrid/releases/download/v#{version}/Volume%20Grid-#{version}.dmg"
  name "Volume Grid"
  desc "Bringing back the classic volume HUD for macOS Tahoe 26 with more."
  homepage "https://github.com/euxx/VolumeGrid"

  depends_on macos: ">= :ventura"

  app "Volume Grid.app"

  uninstall quit: "euxx.volumegrid"
end
