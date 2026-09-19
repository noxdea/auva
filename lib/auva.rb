# frozen_string_literal: true

require "optparse"
require "zlib"
require "kochab"
require "zaniah"
require_relative "auva/version"

module Auva
  class Error < StandardError
    attr_reader :path, :line

    def initialize(message, path: nil, line: nil)
      @path = path
      @line = line
      suffix = [line && "line #{line}", path && path.join(".")].compact.join(": ")
      super(suffix.empty? ? message : "#{message} (#{suffix})")
    end
  end

  PAIRS = [
    %w[text background], %w[text_muted background], %w[text surface],
    %w[accent_text accent], %w[text_inverse accent], %w[text surface_hover]
  ].freeze
  Contrast = Data.define(:pair, :ratio, :aa, :aaa)

  module_function

  def load(path)
    source = File.read(path, encoding: "UTF-8")
    document = Kochab.parse(source)
    tokens = document.value
    raise Error, "top-level tokens must be an object" unless tokens.is_a?(Hash)

    ThemeBuilder.new(tokens, document).call
  rescue Errno::ENOENT
    raise Error, "token file not found: #{path}"
  rescue Kochab::ParseError => error
    first = error.errors.find { |entry| entry.severity == :error }
    line = first && source&.byteslice(0...first.range.begin).to_s.count("\n") + 1
    raise Error.new(error.message, line: line)
  end

  def builtin(name)
    case name.to_s
    when "dark" then Zaniah::Theme.dark
    when "light" then Zaniah::Theme.light
    when "high_contrast", "high-contrast" then Zaniah::Theme.high_contrast
    when "none" then Zaniah::Theme.dark
    else raise Error, "unknown built-in theme: #{name}"
    end
  end

  def contrast(theme, pairs: PAIRS)
    pairs.map do |foreground, background|
      fg = theme.colors.public_send(foreground)
      bg = theme.colors.public_send(background)
      ratio = fg.contrast_ratio(bg)
      Contrast.new(pair: "#{foreground} / #{background}", ratio: ratio,
        aa: ratio >= 4.5, aaa: ratio >= 7.0)
    end
  end

  class ThemeBuilder
    def initialize(tokens, document)
      @tokens = tokens
      @document = document
      @base = Auva.builtin(tokens.fetch("extends", "dark"))
    end

    def call
      validate_top_level
      @base.with(
        colors: build_colors,
        typography: build_data(:typography),
        motion: build_data(:motion),
        spacing: build_hash(:spacing, integer_keys: true),
        radii: build_hash(:radii, symbol_keys: true),
        shadows: build_shadows
      )
    end

    private

    def validate_top_level
      unknown = @tokens.keys.map(&:to_s) - %w[extends colors typography spacing radii shadows motion]
      raise_token("unknown token category: #{unknown.join(", ")}", [unknown.first]) unless unknown.empty?
      base = @tokens["extends"]
      unless base.nil? || %w[dark light high_contrast high-contrast none].include?(base)
        raise_token("extends must be dark, light, high_contrast, or none", ["extends"])
      end
    end

    def build_colors
      values = @tokens.fetch("colors", {})
      ensure_hash(values, ["colors"])
      validate_keys(values, @base.colors.members.map(&:to_s), ["colors"])
      overrides = values.to_h { |key, value| [key.to_sym, parse_color(value, ["colors", key])] }
      @base.colors.with(**overrides)
    end

    def build_data(category)
      values = @tokens.fetch(category.to_s, {})
      ensure_hash(values, [category.to_s])
      validate_keys(values, @base.public_send(category).members.map(&:to_s), [category.to_s])
      converted = values.to_h { |key, value| [key.to_sym, convert_scalar(value, [category.to_s, key])] }
      @base.public_send(category).with(**converted)
    end

    def build_hash(category, integer_keys: false, symbol_keys: false)
      values = @tokens.fetch(category.to_s, {})
      ensure_hash(values, [category.to_s])
      base = @base.public_send(category)
      values.each_with_object(base.dup) do |(key, value), result|
        normalized = integer_keys ? Integer(key, 10) : (symbol_keys ? key.to_sym : key)
        result[normalized] = numeric(value, [category.to_s, key])
      rescue ArgumentError
        raise_token("#{category} key must be numeric", [category.to_s, key])
      end.freeze
    end

    def build_shadows
      values = @tokens.fetch("shadows", {})
      ensure_hash(values, ["shadows"])
      validate_keys(values, @base.shadows.keys.map(&:to_s), ["shadows"])
      values.each_with_object(@base.shadows.dup) do |(key, value), result|
        ensure_hash(value, ["shadows", key])
        result[key.to_sym] = Zaniah::Shadow.new(**value.transform_keys(&:to_sym))
      end.freeze
    end

    def validate_keys(values, known, path)
      unknown = values.keys.map(&:to_s) - known
      raise_token("unknown token: #{unknown.join(", ")}", path + [unknown.first]) unless unknown.empty?
    end

    def ensure_hash(value, path)
      raise_token("expected an object", path) unless value.is_a?(Hash)
    end

    def convert_scalar(value, path)
      value.is_a?(String) && path.first == "motion" && path.last.to_s.start_with?("easing_") ? value.to_sym : value
    end

    def numeric(value, path)
      raise_token("expected a number", path) unless value.is_a?(Numeric)
      value
    end

    def parse_color(value, path)
      Zaniah::Color.parse(value)
    rescue ArgumentError, TypeError
      raise_token("invalid color", path)
    end

    def raise_token(message, path)
      range = @document.range_of(path.compact)
      line = range && @document.text.byteslice(0...range.begin).count("\n") + 1
      raise Error.new(message, path: path.compact, line: line)
    end
  end

  class Png
    def self.write(theme, path, width: 800, height: 480)
      colors = theme.colors.members.map { |name| theme.colors.public_send(name) }
      background = rgba(theme.colors.background)
      pixels = Array.new(width * height, background)
      colors.each_with_index do |color, index|
        x0 = (index % 5) * (width / 5)
        y0 = 60 + (index / 5) * 100
        value = rgba(color)
        (y0...[y0 + 70, height].min).each do |y|
          (x0...[x0 + width / 5, width].min).each { |x| pixels[y * width + x] = value }
        end
      end
      File.binwrite(path, encode(width, height, pixels))
    end

    def self.encode(width, height, pixels)
      raw = (0...height).map { |y| "\0".b + pixels.slice(y * width, width).join }.join
      png_chunk("IHDR", [width, height, 8, 6, 0, 0, 0].pack("NNCCCCC")) +
        png_chunk("IDAT", Zlib::Deflate.deflate(raw)) + png_chunk("IEND", "")
    end

    def self.rgba(color)
      color.to_a.map { |channel| (channel.clamp(0, 1) * 255).round }.pack("C4")
    end
    private_class_method :rgba

    def self.png_chunk(type, payload)
      [payload.bytesize, type, payload, Zlib.crc32(type + payload)].pack("N a4 a* N")
    end
    private_class_method :png_chunk
  end

  class CLI
    def self.run(argv, out: $stdout, err: $stderr)
      options = {check: false, strict: false, export: nil, builtin: nil}
      parser = OptionParser.new do |opts|
        opts.banner = "Usage: auva [TOKENS.jsonc] [options]"
        opts.on("--builtin NAME", "use dark, light, or high_contrast") { |v| options[:builtin] = v }
        opts.on("--check", "check WCAG contrast") { options[:check] = true }
        opts.on("--strict", "fail when AA is not met") { options[:strict] = true }
        opts.on("--export DIR", "write a deterministic palette PNG") { |v| options[:export] = v }
      end
      parser.parse!(argv)
      theme = options[:builtin] ? Auva.builtin(options[:builtin]) : Auva.load(argv.fetch(0))
      results = Auva.contrast(theme)
      if options[:check] || options[:strict]
        results.each { |result| out.puts "#{result.pair}: #{format("%.2f", result.ratio)}:1 #{result.aaa ? "AAA" : result.aa ? "AA" : "FAIL"}" }
      end
      if options[:export]
        Dir.mkdir(options[:export]) unless Dir.exist?(options[:export])
        Png.write(theme, File.join(options[:export], "colors.png"))
      end
      options[:strict] && results.any? { |result| !result.aa } ? 1 : 0
    rescue OptionParser::ParseError, KeyError, Error => error
      err.puts "auva: #{error.message}"
      1
    end
  end
end
