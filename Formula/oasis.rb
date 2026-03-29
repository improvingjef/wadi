class Oasis < Formula
  desc "Dune-free OCaml workspace toolbox"
  homepage "https://github.com/jef/oasis"
  url "https://github.com/jef/oasis/releases/download/v0.1.0/oasis-0.1.0-source.tar.gz"
  sha256 "4d9d4c87fb32ccb8dbbc292329a15a3d89dcf57fda10e5bc30b81d0006b2cf07"
  license "MIT"

  depends_on "ocaml"
  depends_on "ocaml-findlib"

  def install
    system "make", "release-artifacts"
    system "bash", "scripts/install_release_tree.sh",
      "--package-root", "package",
      "--binary", "_bootstrap/bin/oasis",
      "--prefix", prefix
  end

  test do
    output = shell_output("#{bin}/oasis docs")
    assert_match "Oasis CLI", output
  end
end
