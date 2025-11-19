cask "volumegrid" do
  version "1.0.0"
  sha256 "PLACEHOLDER_SHA256_HASH"

  url "https://github.com/euxx/volume-grid/releases/download/v#{version}/VolumeGrid-#{version}.dmg"
  name "Volume Grid"
  desc "Bringing back the classic volume HUD for macOS Tahoe 26 with more."
  homepage "https://github.com/euxx/volume-grid"

  auto_updates true
  depends_on macos: ">= :sonoma"

  app "Volume Grid.app"

  uninstall quit: "one.eux.volumegrid"

  zap trash: [
    "~/Library/Preferences/one.eux.volumegrid.plist",
    "~/Library/Application Support/VolumeGrid",
    "~/Library/Caches/one.eux.volumegrid",
    "~/Library/Logs/VolumeGrid",
    "~/Library/Saved Application State/one.eux.volumegrid.savedState",
  ]
end
