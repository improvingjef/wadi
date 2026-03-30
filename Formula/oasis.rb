class Oasis < Formula
  desc "Dune-free OCaml workspace toolbox"
  homepage "https://github.com/jef/oasis"
  url "https://github.com/jef/oasis/releases/download/v0.1.0/oasis-0.1.0-source.tar.gz"
  sha256 "7c67ddeb5d7340d85aece84316a9aaa4dec91c96c4df6b989d5cbc886d37467c"
  license "MIT"

  depends_on "ocaml"
  depends_on "ocaml-findlib"

  def install
    system "make", "release-artifacts"
    system "./scripts/install_release_tree.sh",
      "--package-root", "package",
      "--binary", "_bootstrap/bin/oasis",
      "--prefix", prefix
  end

  test do
    output = shell_output("#{bin}/oasis docs")
    assert_match "Oasis CLI", output
  end
end
