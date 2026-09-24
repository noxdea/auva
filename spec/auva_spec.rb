# frozen_string_literal: true

require "tempfile"
require "fileutils"
require "stringio"
require "json"

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

  it "accepts every Zaniah syntax token and inherits unspecified ones" do
    skip "Zaniah syntax is unavailable" unless Zaniah::Theme.light.respond_to?(:syntax)
    names = %w[keyword string comment number function type constant punctuation operator variable text]
    file = Tempfile.new(["syntax", ".jsonc"])
    file.write(JSON.generate("extends" => "light", "syntax" => names.to_h { |name| [name, "#123456"] }))
    file.close

    theme = Auva.load(file.path)

    expect(theme.syntax.members.map(&:to_s)).to eq(names)
    names.each { |name| expect(theme.syntax.public_send(name)).to eq(Zaniah::Color.parse("#123456")) }
    expect(Auva.builtin("light").syntax.keyword).not_to eq(theme.syntax.keyword)
    File.write(file.path, JSON.generate("extends" => "light", "syntax" => {"keyword" => "#123456"}))
    partial = Auva.load(file.path)
    expect(partial.syntax.string).to eq(Auva.builtin("light").syntax.string)
  ensure
    file&.unlink
  end

  it "reports unknown and invalid syntax colors with their token locations" do
    skip "Zaniah syntax is unavailable" unless Zaniah::Theme.light.respond_to?(:syntax)
    file = Tempfile.new(["syntax", ".jsonc"])
    file.write("{\n  \"syntax\": { \"keyword\": \"not-a-color\" }\n}\n")
    file.close
    expect { Auva.load(file.path) }.to raise_error(Auva::Error, /invalid color \(line 2: syntax.keyword\)/)
    File.write(file.path, "{\n  \"syntax\": { \"unknown\": \"#fff\" }\n}\n")
    expect { Auva.load(file.path) }.to raise_error(Auva::Error, /unknown token.*line 2: syntax.unknown/)
  ensure
    file&.unlink
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
    expect(Dir[File.join(directory, "nested", "*.png")].map { |path| File.basename(path) }).to include("colors.png", "typography.png", "buttons.png")
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

  it "renders a named preview category" do
    expect(Auva::Preview.render(Zaniah::Theme.dark, category: :components).byteslice(0, 4)).to eq("\x89PNG".b)
    expect { Auva::Preview.render(Zaniah::Theme.dark, category: :unknown) }.to raise_error(Auva::Error)
  end

  it "builds a native preview element without requiring a window" do
    expect(Auva::Preview.element(Zaniah::Theme.dark, category: :components)).to be_a(Zaniah::Div)
    expect(Auva::Preview::COMPONENT_COUNT).to be >= 20
  end

  it "builds the full typography scale preview" do
    expect(Auva::Preview.element(Zaniah::Theme.dark, category: :typography)).to be_a(Zaniah::Div)
  end

  it "renders token categories from the active theme" do
    %i[spacing radii shadows motion buttons].each do |category|
      bytes = Auva::Preview.render(Zaniah::Theme.dark, category: category, width: 320, height: 240)
      expect(bytes.byteslice(0, 8)).to eq("\x89PNG\r\n\x1a\n".b)
      expect(bytes).to eq(Auva::Preview.render(Zaniah::Theme.dark, category: category, width: 320, height: 240))
    end
  end

  it "falls back when the native preview backend is unavailable" do
    output = StringIO.new
    allow(output).to receive(:tty?).and_return(true)
    allow(Auva::Preview).to receive(:show).and_raise(SystemCallError, "backend unavailable")
    expect(Auva::CLI.run(["--builtin", "dark"], out: output, err: StringIO.new)).to eq(0)
    expect(output.string).to include("loaded 1 theme")
  end

  it "builds switchable theme tabs for the preview" do
    tabs = Auva::Preview.send(:build_theme_tabs, [["dark", Zaniah::Theme.dark], ["light", Zaniah::Theme.light]], :colors)
    expect(tabs).to be_a(Zaniah::UI::Tabs)
  end
end
