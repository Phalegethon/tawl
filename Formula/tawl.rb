# Generated from the checksums of the final release assets.
class Tawl < Formula
  desc "macOS terminal system monitor and flight recorder"
  homepage "https://github.com/Phalegethon/tawl"
  version "0.1.0"
  license "MIT"

  depends_on :macos

  on_macos do
    depends_on macos: :sequoia
  end

  on_arm do
    url "https://github.com/Phalegethon/tawl/releases/download/v0.1.0/tawl-0.1.0-macos-arm64.tar.gz"
    sha256 "7e8bcb313394d5b038473dd2e22799eb9d814c58187842c0ea3faa0cfbae9930"
  end

  on_intel do
    url "https://github.com/Phalegethon/tawl/releases/download/v0.1.0/tawl-0.1.0-macos-x86_64.tar.gz"
    sha256 "8f840b234f5e27a4a425d165008267c520ab6443a532bcc9d9197fbc48cf87d6"
  end

  def install
    bin.install "tawl"
    pkgshare.install "LICENSE"
  end

  test do
    assert_equal "tawl #{version}", shell_output("#{bin}/tawl --version").strip
  end
end
