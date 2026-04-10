class Wadi < Formula
  desc "Dune-free OCaml workspace toolbox"
  homepage "https://github.com/jef/wadi"
  url "https://github.com/jef/wadi/releases/download/v0.1.0/wadi-0.1.0-source.tar.gz"
  sha256 "27e23d15baa10cdfb0f5917e718703b014b784bdd9fb12ecfb344fab4b1cc502"
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
