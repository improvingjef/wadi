class Wadi < Formula
  desc "Dune-free OCaml workspace toolbox"
  homepage "https://github.com/jef/wadi"
  url "https://github.com/jef/wadi/releases/download/v0.1.0/wadi-0.1.0-source.tar.gz"
  sha256 "d0083cd730f3d20ca24d6d877026fb20b304b3d5ffdb4a981a71c0625f9e6ed7"
  license "MIT"

  depends_on "ocaml"
  depends_on "ocaml-findlib"

  def install
    system "make", "release-artifacts"
    system "./scripts/install_release_tree.sh",
      "--package-root", "package",
      "--binary", "_bootstrap/bin/wadi",
      "--prefix", prefix
  end

  test do
    output = shell_output("#{bin}/wadi docs")
    assert_match "Wadi CLI", output
  end
end
