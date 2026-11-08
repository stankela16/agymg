class Agymg < Formula
  desc "Share MCP servers, skills, and plugins across Claude Code and Antigravity"
  homepage "https://github.com/stankela16/agymg"
  url "https://github.com/stankela16/agymg/archive/refs/tags/v1.0.1.tar.gz"
  sha256 "54800190eb38a148f722c077083876dafdfe74608cf6214c61255c8d602ade55"
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
    assert_match "agymg 1.0.1", shell_output("#{bin}/agymg --version")
  end
end
