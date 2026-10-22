# Generated from the checksums of the final release assets.
class Tawl < Formula
  desc "macOS terminal system monitor and flight recorder"
  homepage "https://github.com/Phalegethon/tawl"
  version "0.2.1"
  license "MIT"

  depends_on :macos

  on_macos do
    depends_on macos: :sequoia
  end

  on_arm do
    url "https://github.com/Phalegethon/tawl/releases/download/v0.2.1/tawl-0.2.1-macos-arm64.tar.gz"
    sha256 "83a928a6244a28f95eb6996e1a19b0e2929946dfd30711ac425015086bb1f415"
  end

  on_intel do
    url "https://github.com/Phalegethon/tawl/releases/download/v0.2.1/tawl-0.2.1-macos-x86_64.tar.gz"
    sha256 "c866dd300c2300da39994624af26e34bcaf0decf1dca0bca3534dd83c1f8c0c0"
  end

  def install
    bin.install "tawl"
    pkgshare.install "LICENSE"
  end

  test do
    assert_equal "tawl #{version}", shell_output("#{bin}/tawl --version").strip
  end
end
