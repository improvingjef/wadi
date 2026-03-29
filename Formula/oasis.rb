class Oasis < Formula
  desc "Dune-free OCaml workspace toolbox"
  homepage "https://github.com/jef/oasis"
  url "https://github.com/jef/oasis/releases/download/v0.1.0/oasis-0.1.0-source.tar.gz"
  sha256 "1a638e6af9aeff63e9328326f7c47aeb9c842fca6cdd4f1634fd3ff1628123a4"
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
