class Ambienta < Formula
  desc "Generate atmospheric / foley background beds from a text prompt or scene preset"
  homepage "https://github.com/intrusive-memory/SwiftAmbiente"
  url "https://github.com/intrusive-memory/SwiftAmbiente/releases/download/v0.1.0/ambienta-0.1.0-arm64-macos.tar.gz"
  sha256 "PLACEHOLDER_SHA256"
  license "MIT"
  version "0.1.0"

  depends_on arch: :arm64
  depends_on macos: :tahoe

  def install
    bin.install "ambienta"
  end

  def caveats
    <<~EOS
      ambienta requires Apple Silicon (M1 or later) and macOS Tahoe (26.0+).

      The shipping engine is a procedural (filtered-noise) generator and needs no
      model download. The neural Stable Audio backend is staged for a future
      release.

      Generate a background bed from a built-in scene:
        ambienta --scene rain -d 30 -o rain.wav

      ...or from a free-form prompt:
        ambienta "distant city traffic, muffled hum" -d 15 -o city.wav

      Run `ambienta --list-scenes` for the built-in presets.
    EOS
  end

  test do
    assert_match "ambienta", shell_output("#{bin}/ambienta --version")
  end
end
