# frozen_string_literal: true

#
# Copyright 2025 whiteleaf. All rights reserved.
#

#
# 正規表現パターンのプリコンパイル
#
# 頻繁に使用される正規表現をあらかじめコンパイルしてパフォーマンスを向上
# 3,895エピソードの変換では、同じパターンが数百万回使用されるため、
# プリコンパイルによる効果は大きい
#
class ConverterBase
  module CompiledPatterns
    # ミニュート関連
    SINGLE_MINUTE_FAMILY = %!'''!
    DOUBLE_MINUTE_FAMILY = %!""〝〟"!
    
    # プリコンパイル済み正規表現パターン
    PATTERNS = {
      # 改行・空白関連
      triple_newline: /(^\n){3}/m,
      blank_line: /\A[ 　\t]*$/,
      page_break: /［＃改ページ］/,
      page_break_auto: /［＃改頁］/,
      
      # 記号・括弧関連
      exclamation_question: /([!?！？]+)([^!?！？])/,
      close_bracket_chars: /[^」］｝\]\}』】〉》〕＞>≫)）""'〟　☆★♪［―]/,
      punctuation_before_close_bracket: /。([」』）])/,
      
      # ミニュート変換
      single_minute_pattern: /[#{SINGLE_MINUTE_FAMILY}]([^"\n]+?)[#{SINGLE_MINUTE_FAMILY}]/,
      double_minute_pattern: /[#{DOUBLE_MINUTE_FAMILY}]([^"\n]+?)[#{DOUBLE_MINUTE_FAMILY}]/,
      
      # 感嘆符・疑問符
      exclamation_only: /！+/,
      exclamation_or_question: /[！？]+/,
      
      # ルビ関連
      ruby_angle: /(.+?)≪([^≪]+?)≫/,
      
      # 数字関連
      digits: /\d+/,
      
      # 英文関連
      english_sentences: /[\w.,!?'" &:;-]+/,
      alphabet_only: /[a-zA-Z]+/,
      lowercase_letter: /[a-z]/i,
      
      # コメントブロック
      comment_block_separator: /^-{50,}$/,
      comment_block_full: /^-{50,}\n.*?^-{50,}\n/m,
      
      # 改ページ
      page_break_tag: /［＃改ページ］/,
      
      # 繰り返し文字
      ellipsis: /…+/,
      double_dot: /‥+/,
      prolonged_sound: /(ー{2,})/,
      
      # 濁点
      dakuten_char: /([ぁ-んァ-ヶι])[゛ﾞ]/,
      
      # 句読点・空白
      punctuation_space: /。　/,
      space_or_punctuation: /[ 、。]/,
      
      # その他
      kbr_tag: /<KBR>/i,
      pbr_tag: /<PBR>/i,
      改ページ文字列: /【改ページ】/,
      
      # StringScanner用パターン
      two_lines: /(.+\n){2}/,
      angle_close: /.+?》/,
      注記_pattern: /^＃.+?］/,
      tag_close: /.+?>/,
      数字_pattern: /[\d０-９]+/,
      ひらがな_pattern: /[ぁ-んゝゞー]+/,
      カタカナ_pattern: /[ァ-ヶー・]+/,
      アルファベット_pattern: /[Ａ-Ｚａ-ｚA-Za-z ]+/,
      漢字_pattern: /[一-龥朗-鶴]+/,

      # insert_word_separator / insert_char_separator 用パターン
      note_pattern: /［＃.+?］/,
      html_pattern: /<.+?>/,
      ruby_pattern: /｜.+?》/,
      open_bracket: /[〔「『\(（【〈《≪〝]/,
      char_symbol_pattern: /[―…!?！？※]/,
      textfile_header_pattern: /(.+\n){2}/
    }.freeze

    # 単語版用: スクリプトごとの塊（一気にスキャン）
    WORD_CHUNK_SCANNER = Regexp.union([
      PATTERNS[:ruby_pattern],
      /[\d０-９]+/,            # 数字
      /[ぁ-んゝゞー]+/,        # ひらがな
      /[ァ-ヶー・]+/,          # カタカナ
      /[Ａ-Ｚａ-ｚA-Za-z ]+/,  # アルファベット
      /[一-龥朗-鶴]+/          # 漢字
    ])
    
    # 置換マップ（複数gsub!を1回のスキャンに最適化）
    NAROU_TAG_REPLACE_MAP = {
      "【改ページ】" => "",
      /<KBR>/i => "\n",
      /<PBR>/i => "\n"
    }.freeze
    NAROU_TAG_PATTERN = Regexp.union(NAROU_TAG_REPLACE_MAP.keys)

    DUST_CHAR_REPLACE_MAP = {
      "︎" => "",
      "︎" => ""
    }.freeze
    DUST_CHAR_PATTERN = Regexp.union(DUST_CHAR_REPLACE_MAP.keys)

    # before()メソッドの改行圧縮用
    BLANK_LINE_COMPRESS_MAP = {
      "\n\n" => "\n",
      /(^\n){3}/m => "\n\n"
    }.freeze
    BLANK_LINE_COMPRESS_PATTERN = Regexp.union(BLANK_LINE_COMPRESS_MAP.keys)
    
    # ローマ数字変換用（動的パターン生成が必要なため個別定義）
    ROME_NUM_ALPHABET = %w(II III IV VI VII VIII IX ii iii iv vi vii viii ix).freeze
    ROME_NUM = %w(Ⅱ Ⅲ Ⅳ Ⅵ Ⅶ Ⅷ Ⅸ ⅱ ⅲ ⅳ ⅵ ⅶ ⅷ ⅸ).freeze
    
    # 単語版用: スクリプトごとの塊（一気にスキャン）
    WORD_CHUNK_SCANNER = Regexp.union([
      /｜.+?》/,               # ルビ
      /[\d０-９]+/,            # 数字
      /[ぁ-んゝゞー]+/,        # ひらがな
      /[ァ-ヶー・]+/,          # カタカナ
      /[Ａ-Ｚａ-ｚA-Za-z ]+/,  # アルファベット
      /[一-龥朗-鶴]+/          # 漢字
    ])
    
    # ローマ数字パターンをキャッシュ（初回アクセス時に生成）
    @rome_patterns = nil
    
    def self.rome_patterns
      @rome_patterns ||= ROME_NUM_ALPHABET.map do |rome|
        /([^a-zA-Z])#{Regexp.escape(rome)}([^a-zA-Z])/
      end.freeze
    end
    
    # パターン取得用ヘルパーメソッド
    def pattern(key)
      PATTERNS[key] || raise("Unknown pattern: #{key}")
    end
    
    # クラスメソッド版（モジュールから直接アクセス可能）
    def self.pattern(key)
      PATTERNS[key] || raise("Unknown pattern: #{key}")
    end
  end
end
