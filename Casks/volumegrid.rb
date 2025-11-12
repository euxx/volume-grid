cask "volumegrid" do
  version "1.0.0"
  sha256 "PLACEHOLDER_SHA256_HASH"

  url "https://github.com/euxx/VolumeGrid/releases/download/v#{version}/VolumeGrid-#{version}.dmg"
  name "VolumeGrid"
  desc "A volume control HUD for macOS"
  homepage "https://github.com/euxx/VolumeGrid"

  depends_on macos: ">= :ventura"

  app "VolumeGrid.app"

  uninstall quit: "euxx.volumegrid"
end
