# Generated from the checksums of the final release assets.
class Tawl < Formula
  desc "macOS terminal system monitor and flight recorder"
  homepage "https://github.com/Phalegethon/tawl"
  version "0.2.0"
  license "MIT"

  depends_on :macos

  on_macos do
    depends_on macos: :sequoia
  end

  on_arm do
    url "https://github.com/Phalegethon/tawl/releases/download/v0.2.0/tawl-0.2.0-macos-arm64.tar.gz"
    sha256 "9de8094a9172cce77e5d069429d8fdcf7b0d78cf31b702f43516a649bd2a804f"
  end

  on_intel do
    url "https://github.com/Phalegethon/tawl/releases/download/v0.2.0/tawl-0.2.0-macos-x86_64.tar.gz"
    sha256 "a328f996b6a16eca8c20fcf30e8661f562ba3c6f070c35ed4b180ae71de50dce"
  end

  def install
    bin.install "tawl"
    pkgshare.install "LICENSE"
  end

  test do
    assert_equal "tawl #{version}", shell_output("#{bin}/tawl --version").strip
  end
end
