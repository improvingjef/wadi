class Oasis < Formula
  desc "Dune-free OCaml workspace toolbox"
  homepage "https://github.com/jef/oasis"
  url "https://github.com/jef/oasis/releases/download/v0.1.0/oasis-0.1.0-source.tar.gz"
  sha256 "a2822f201417a2c08268f9a1fcf021654b2dc65ba263c4e7a43a1f96c5e5c9cb"
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
