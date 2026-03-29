class Oasis < Formula
  desc "Dune-free OCaml workspace toolbox"
  homepage "https://github.com/jef/oasis"
  url "https://github.com/jef/oasis/releases/download/v0.1.0/oasis-0.1.0-source.tar.gz"
  sha256 "d23453dd564404170d752b0c0d4a1b8d5bb7012774f8e3c009929964a9308ed8"
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
