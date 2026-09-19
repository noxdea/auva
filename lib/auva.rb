# frozen_string_literal: true

require "optparse"
require "fileutils"
require "zlib"
require "kochab"
require "zaniah"
require "zaniah/ui"
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
      converted = values.to_h do |key, value|
        path = [category.to_s, key]
        converted_value = convert_scalar(value, path)
        validate_scalar(converted_value, @base.public_send(category).public_send(key.to_sym), path)
        [key.to_sym, converted_value]
      end
      @base.public_send(category).with(**converted)
    end

    def build_hash(category, integer_keys: false, symbol_keys: false)
      values = @tokens.fetch(category.to_s, {})
      ensure_hash(values, [category.to_s])
      base = @base.public_send(category)
      validate_keys(values, base.keys.map(&:to_s), [category.to_s]) if symbol_keys
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
        known = Zaniah::Shadow.members.map(&:to_s)
        validate_keys(value, known, ["shadows", key])
        converted = value.transform_keys(&:to_sym)
        converted[:color] = parse_color(converted[:color], ["shadows", key, "color"]) if converted.key?(:color)
        %i[x y blur spread].each do |name|
          next unless converted.key?(name)
          raise_token("expected a number", ["shadows", key, name]) unless converted[name].is_a?(Numeric)
        end
        raise_token("expected a boolean", ["shadows", key, "inset"]) unless !converted.key?(:inset) || converted[:inset] == true || converted[:inset] == false
        result[key.to_sym] = @base.shadows.fetch(key.to_sym).with(**converted)
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

    def validate_scalar(value, base, path)
      valid = case base
      when Numeric then value.is_a?(Numeric)
      when Symbol then value.is_a?(Symbol)
      when String then value.is_a?(String)
      when TrueClass, FalseClass then value == true || value == false
      else true
      end
      raise_token("invalid value", path) unless valid
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
    def self.write(theme, path, width: 800, height: 480, category: :colors)
      File.binwrite(path, bytes(theme, width: width, height: height, category: category))
    end

    def self.bytes(theme, width: 800, height: 480, category: :colors)
      colors = category_colors(theme, category)
      background = rgba(theme.colors.background)
      pixels = Array.new(width * height, background)
      colors.each_with_index do |color, index|
        x0 = (index % 5) * (width / 5)
        y0 = 60 + (index / 5) * 100 + category_offset(category)
        value = rgba(color)
        (y0...[y0 + 70, height].min).each do |y|
          (x0...[x0 + width / 5, width].min).each { |x| pixels[y * width + x] = value }
        end
      end
      encode(width, height, pixels)
    end

    def self.write_sheets(theme, directory)
      FileUtils.mkdir_p(directory)
      %w[colors typography spacing radii shadows motion buttons components].each do |category|
        write(theme, File.join(directory, "#{category}.png"), category: category.to_sym)
      end
    end

    def self.category_colors(theme, category)
      names = case category.to_sym
      when :buttons then %i[accent accent_hover text_inverse]
      when :typography then %i[text text_muted accent]
      when :spacing then %i[accent info]
      when :radii then %i[accent_hover accent]
      when :shadows then %i[overlay_scrim border_focus]
      when :motion then %i[success warning danger]
      when :components then %i[accent success warning danger info]
      else theme.colors.members
      end
      names.map { |name| theme.colors.public_send(name) }
    end

    def self.category_offset(category)
      category.to_s.bytes.sum % 31
    end
    private_class_method :category_colors, :category_offset

    def self.encode(width, height, pixels)
      raw = (0...height).map { |y| "\0".b + pixels.slice(y * width, width).join }.join
      "\x89PNG\r\n\x1a\n".b + png_chunk("IHDR", [width, height, 8, 6, 0, 0, 0].pack("NNCCCCC")) +
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

  class Preview
    CATEGORIES = %i[colors typography spacing radii shadows motion buttons components].freeze
    COMPONENT_COUNT = 31
    GalleryItem = Data.define(:name, :component) do
      def label = name
    end

    def self.render(theme, category: :colors, width: 800, height: 480)
      raise Error, "unknown preview category: #{category}" unless CATEGORIES.include?(category.to_sym)
      Png.bytes(theme, width: width, height: height, category: category)
    end

    def self.render_all(theme, directory)
      Png.write_sheets(theme, directory)
    end

    def self.element(theme, category: :colors)
      category = category.to_sym
      raise Error, "unknown preview category: #{category}" unless CATEGORIES.include?(category)
      return component_gallery(theme) if category == :components
      return typography_preview(theme) if category == :typography
      colors = Png.send(:category_colors, theme, category)
      title = Zaniah::Text.new("Auva · #{category}", size: 26, color: theme.colors.text)
      root = Zaniah::Div.new.flex_col.p(32).gap(12).bg(theme.colors.background).child(title)
      colors.each_with_index do |color, index|
        swatch = Zaniah::Div.new.w(36).h(36).bg(color)
        root = root.child(Zaniah::Div.new.flex_row.gap(12).items_center.child(swatch).child(
          Zaniah::Text.new("#{category}[#{index}]", size: 16, color: theme.colors.text)
        ))
      end
      root
    end

    def self.typography_preview(theme)
      sizes = %i[xs sm md lg xl] + ["2xl"]
      body = Zaniah::Div.new.flex_col.gap(12).children(sizes.map do |size|
        Zaniah::UI::Card.new(
          Zaniah::UI::Label.new(size.to_s, tone: :muted, size: :xs),
          size == "2xl" ? Zaniah::Text.new("Aa あいう漢字 — #{size}", size: theme.typography.size_2xl, color: theme.colors.text) :
            Zaniah::UI::Label.new("Aa あいう漢字 — #{size}", size: size, wrap: :word)
        )
      end)
      Zaniah::Div.new.flex_col.p(32).gap(12).bg(theme.colors.background)
        .child(Zaniah::UI::Label.new("Auva · typography", size: :xl)).child(Zaniah::ScrollView.new(scrollbar: :always).flex_1.child(body))
    end

    def self.component_gallery(theme)
      rows = [
        ["Button", Zaniah::UI::Button.new("Primary")],
        ["IconButton", Zaniah::UI::IconButton.new(:info, label: "Info")],
        ["ToggleButton", Zaniah::UI::ToggleButton.new("Toggle", value: true)],
        ["ButtonGroup", Zaniah::UI::ButtonGroup.new(Zaniah::UI::Button.new("One"), Zaniah::UI::Button.new("Two", variant: :secondary))],
        ["Checkbox", Zaniah::UI::Checkbox.new("Accept", value: true)],
        ["Radio", Zaniah::UI::Radio.new("Choice", value: true)],
        ["RadioGroup", Zaniah::UI::RadioGroup.new([["Dark", :dark], ["Light", :light]], value: :dark)],
        ["Switch", Zaniah::UI::Switch.new("Enabled", value: true)],
        ["Slider", Zaniah::UI::Slider.new(value: 65, label: "Volume")],
        ["RangeSlider", Zaniah::UI::RangeSlider.new(value: [20, 80])],
        ["ProgressBar", Zaniah::UI::ProgressBar.new(value: 72)],
        ["Spinner", Zaniah::UI::Spinner.new],
        ["Badge", Zaniah::UI::Badge.new("New", variant: :success)],
        ["Card", Zaniah::UI::Card.new(Zaniah::UI::Label.new("Card content"))],
        ["TextField", Zaniah::UI::TextField.new("Example", label: "Name")],
        ["TextArea", Zaniah::UI::TextArea.new("Longer text", rows: 2, label: "Description")],
        ["Select", Zaniah::UI::Select.new([["Dark", :dark], ["Light", :light]], value: :dark)],
        ["MultiSelect", Zaniah::UI::MultiSelect.new(%w[Ruby UI], value: ["Ruby"])],
        ["Tabs", Zaniah::UI::Tabs.new([["Overview", Zaniah::UI::Label.new("Overview")], ["Details", Zaniah::UI::Label.new("Details")]])],
        ["Accordion", Zaniah::UI::Accordion.new([["Details", Zaniah::UI::Label.new("Expanded content")]], open: [0])],
        ["Breadcrumb", Zaniah::UI::Breadcrumb.new(["Home", "Design", "Preview"])],
        ["Pagination", Zaniah::UI::Pagination.new(page: 2, pages: 4)],
        ["Table", Zaniah::UI::Table.new([{name: "Alpha", value: "1"}, {name: "Beta", value: "2"}], columns: [
          {key: :name, label: "Name", width: 160, sortable: false}, {key: :value, label: "Value", width: 100, sortable: false}
        ], height: 110, selection: :none)],
        ["ListView", Zaniah::UI::ListView.new(%w[First Second Third], height: 100)],
        ["TreeView", Zaniah::UI::TreeView.new([{id: :root, label: "Root", children: [{id: :leaf, label: "Leaf"}]}], height: 100)],
        ["EmptyState", Zaniah::UI::EmptyState.new("Nothing here", message: "Add an item to continue")],
        ["Sparkline", Zaniah::UI::Sparkline.new([1, 3, 2, 5])],
        ["BarChart", Zaniah::UI::BarChart.new({"Build" => [2, 4, 3]}, width: 240, height: 100)],
        ["RichText", Zaniah::UI::RichText.new([{text: "Highlighted", color: theme.colors.accent}, " text"])],
        ["Divider", Zaniah::UI::Divider.new],
        ["StatusBar", Zaniah::UI::StatusBar.new(Zaniah::UI::Label.new("Ready"), Zaniah::UI::Badge.new("OK", variant: :success))]
      ]
      items = rows.map { |name, component| GalleryItem.new(name, component) }
      body = Zaniah::UI::ListView.new(items, height: 560, row_height: 180) do |item, _index|
        Zaniah::UI::Card.new(Zaniah::UI::Label.new(item.name, tone: :muted, size: :xs), item.component)
      end
      Zaniah::Div.new.flex_col.p(32).gap(12).bg(theme.colors.background)
        .child(Zaniah::UI::Label.new("Auva · components (#{rows.length})", size: :xl))
        .child(Zaniah::ScrollView.new(scrollbar: :always).flex_1.child(body))
    end

    def self.show(theme, category: :colors, backend: :auto, watcher: nil, title: "Auva")
      selected = backend == :auto ? (RUBY_PLATFORM.include?("darwin") ? :mac : RUBY_PLATFORM.match?(/mswin|mingw/) ? :windows : :linux) : backend
      window = Zaniah::Platform.open_window(backend: selected, width: 800, height: 600, title: title)
      current = theme
      window.draw { element(current, category: category) }
      window.on_tick do
        if watcher&.poll
          current = watcher.theme unless watcher.error
          window.request_frame
        end
      end
      window.run
    ensure
      window&.close
    end
  end

  class Watcher
    attr_reader :theme, :error

    def initialize(path, theme: nil, latency: 0.1)
      @path, @theme, @latency, @last = path, theme || Auva.load(path), latency, File.mtime(path)
      @watch = begin
        Zaniah::Platform.watch(File.dirname(File.expand_path(path)), latency: latency)
      rescue StandardError => error
        @error = error
        nil
      end
    end

    def poll
      events = @watch.poll(timeout: 0)
      changed = events.any? { |event| File.expand_path(event.path) == File.expand_path(@path) }
      changed ||= File.file?(@path) && File.mtime(@path) != @last
      return false unless changed
      @last = File.mtime(@path)
      @theme = Auva.load(@path)
      @error = nil
      true
    rescue StandardError => error
      @error = error
      false
    end
  end

  class CLI
    def self.run(argv, out: $stdout, err: $stderr)
      options = {check: false, strict: false, export: nil, builtin: nil, themes: nil, no_watch: false, watch: false}
      parser = OptionParser.new do |opts|
        opts.banner = "Usage: auva [TOKENS.jsonc] [options]"
        opts.on("--builtin NAME", "use dark, light, or high_contrast") { |v| options[:builtin] = v }
        opts.on("--check", "check WCAG contrast") { options[:check] = true }
        opts.on("--strict", "fail when AA is not met") { options[:strict] = true }
        opts.on("--export DIR", "write a deterministic palette PNG") { |v| options[:export] = v }
        opts.on("--themes NAMES", "comma-separated built-in themes") { |v| options[:themes] = v.split(",").map(&:strip) }
        opts.on("--no-watch", "disable file watching") { options[:no_watch] = true }
        opts.on("--watch", "watch token files until interrupted") { options[:watch] = true }
      end
      parser.parse!(argv)
      names = options[:themes] || [options[:builtin] || "file"]
      source_path = argv.first
      themes = names.map { |name| name == "file" ? Auva.load(argv.fetch(0)) : Auva.builtin(name) }
      failures = themes.each_with_index.sum do |theme, index|
        results = Auva.contrast(theme)
        if options[:check] || options[:strict]
          results.each { |result| out.puts "#{result.pair}: #{format("%.2f", result.ratio)}:1 #{result.aaa ? "AAA" : result.aa ? "AA" : "FAIL"}" }
        end
        if options[:export]
          destination = themes.length == 1 ? options[:export] : File.join(options[:export], names[index])
          Png.write_sheets(theme, destination)
        end
        results.count { |result| !result.aa }
      end
      if !options[:export] && !options[:check] && !options[:strict] && out.tty? && defined?(Zaniah::Platform)
        watcher = source_path && !options[:builtin] && !options[:themes] ? Watcher.new(source_path) : nil
        Preview.show(themes.first, watcher: watcher, title: "Auva · #{names.first}")
        return 0
      end
      if options[:watch] && !options[:no_watch] && source_path && !options[:builtin] && !options[:themes]
        watcher = Watcher.new(source_path)
        out.puts "auva: watching #{source_path}"
        loop do
          sleep 0.1
          if watcher.poll
            out.puts watcher.error ? "auva: #{watcher.error.message}" : "auva: updated"
          end
        end
      end
      out.puts "auva: loaded #{themes.length} theme(s)" unless options[:check] || options[:strict] || options[:export]
      options[:strict] && failures.positive? ? 1 : 0
    rescue OptionParser::ParseError, KeyError, Error => error
      err.puts "auva: #{error.message}"
      1
    end
  end
end
