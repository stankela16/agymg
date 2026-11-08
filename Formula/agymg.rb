class Agymg < Formula
  desc "Share MCP servers, skills, and plugins across Claude Code and Antigravity"
  homepage "https://github.com/stankela16/agymg"
  url "https://github.com/stankela16/agymg/archive/refs/tags/v1.0.0.tar.gz"
  sha256 "7cb198399bfe6476e5a5bce3ebef355ca6bbf77f891c18546f655f908dc72704"
  license "MIT"
  head "https://github.com/stankela16/agymg.git", branch: "main"

  depends_on macos: :sonoma

  def install
    system "./Scripts/package_app.sh", "release"
    libexec.install "agymg.app"
    bin.install_symlink libexec/"agymg.app/Contents/MacOS/agymg" => "agymg"
  end

  def caveats
    <<~EOS
      To copy agymg.app into /Applications (for Spotlight, Launchpad, and Launch at Login):
        agymg install-app

      Or launch it directly from Homebrew's prefix:
        open "#{opt_libexec}/agymg.app"
    EOS
  end

  test do
    assert_match "agymg", shell_output("#{bin}/agymg --version")
  end
end
