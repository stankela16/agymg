class Agymg < Formula
  desc "Share MCP servers, skills, and plugins across Claude Code and Antigravity"
  homepage "https://github.com/stankela16/agymg"
  url "https://github.com/stankela16/agymg/archive/refs/tags/v1.0.0.tar.gz"
  sha256 "ca9c5e72f2b9d004bdaba633a1ad4291b61f548b9de80201285ba58a2aa3fb84"
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
