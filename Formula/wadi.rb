class Wadi < Formula
  desc "Dune-free OCaml workspace toolbox"
  homepage "https://github.com/improvingjef/wadi"
  url "https://github.com/improvingjef/wadi/releases/download/v0.1.0/wadi-0.1.0-source.tar.gz"
  sha256 "0834b4efd8e0eb22c54d8ca635fad844e4c730604e59a561f331b54ba0513aaa"
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
