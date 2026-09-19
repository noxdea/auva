# frozen_string_literal: true

require "tempfile"
require "fileutils"

RSpec.describe Auva do
  let(:tokens) do
    Tempfile.new(["tokens", ".jsonc"]).tap do |file|
      file.write(<<~JSONC)
        {
          // comments are valid JSONC
          "extends": "light",
          "colors": { "accent": "#245b9b" },
          "motion": { "reduced": true }
        }
      JSONC
      file.close
    end
  end

  it "loads JSONC tokens into a theme" do
    theme = Auva.load(tokens.path)
    expect(theme).to be_a(Zaniah::Theme)
    expect(theme.colors.accent).to eq(Zaniah::Color.parse("#245b9b"))
    expect(theme.motion.reduced?).to be(true)
  ensure
    tokens&.unlink
  end

  it "reports unknown keys with a source line" do
    file = Tempfile.new(["tokens", ".jsonc"])
    file.write("{\n  \"colors\": { \"typo\": \"#fff\" }\n}\n")
    file.close
    expect { Auva.load(file.path) }.to raise_error(Auva::Error, /line 2/)
  ensure
    file&.unlink
  end

  it "computes the known black and white ratio" do
    expect(Zaniah::Color.parse("#000").contrast_ratio(Zaniah::Color.parse("#fff"))).to eq(21.0)
  end

  it "writes deterministic category sheets" do
    directory = Dir.mktmpdir("auva")
    expect(Auva::CLI.run(["--builtin", "dark", "--export", File.join(directory, "nested")])).to eq(0)
    expect(Dir[File.join(directory, "nested", "*.png")].map { |path| File.basename(path) }).to include("colors.png", "typography.png")
  ensure
    FileUtils.remove_entry(directory) if directory
  end

  it "reports malformed shadow members as token errors" do
    file = Tempfile.new(["tokens", ".jsonc"])
    file.write('{"shadows":{"sm":{"wat":"x"}}}')
    file.close
    expect { Auva.load(file.path) }.to raise_error(Auva::Error, /unknown token/)
  ensure
    file&.unlink
  end
end
