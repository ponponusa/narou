# -*- mode: ruby -*-
# -*- coding: utf-8 -*-
root = File.expand_path("..", __FILE__)
$LOAD_PATH.unshift(root) unless $LOAD_PATH.include?(root)
require "lib/core/version"  # $LOAD_PATHにプロジェクトルートが追加されているので、lib/からの相対パス
require "fileutils"
module Narou
  def self.create_git_commit_version
    File.write("commitversion", `git describe --always`.strip)
    "commitversion"
  end

  # フロントエンドのビルド（コミットIDが異なる場合のみ実行）
  def self.build_frontend_if_needed
    frontend_dir = File.join(File.dirname(__FILE__), "frontend")
    dist_dir = File.join(frontend_dir, "dist")
    commit_file = File.join(dist_dir, ".build-commit")

    # 現在のコミットIDを取得
    current_commit = `git describe --always`.strip

    # 既存のビルドコミットIDと比較
    if File.exist?(commit_file)
      built_commit = File.read(commit_file).strip
      if built_commit == current_commit
        # コミットIDが一致すればビルド不要
        return
      end
    end

    # npm が利用可能かチェック
    npm_available = system("npm --version > #{Gem.win_platform? ? 'NUL' : '/dev/null'} 2>&1")
    unless npm_available
      warn "WARNING: npm is not available. Skipping frontend build."
      warn "         Run 'npm run build' in frontend/ directory manually."
      return
    end

    warn "Building frontend (commit: #{current_commit})..."
    Dir.chdir(frontend_dir) do
      unless system("npm ci --silent")
        warn "WARNING: npm ci failed"
        return
      end
      unless system("npm run build --silent")
        warn "WARNING: npm run build failed"
        return
      end
    end

    # ビルド成功時にコミットIDを記録
    FileUtils.mkdir_p(dist_dir)
    File.write(commit_file, current_commit)
    warn "Frontend build completed."
  end
end
Encoding.default_external = Encoding::UTF_8

# gem build 時にフロントエンドをビルド
Narou.build_frontend_if_needed

Gem::Specification.new do |gem|
  gem.name          = "narou-mod"
  gem.version       = ::Narou::VERSION
  gem.license       = "MIT"
  gem.authors       = ["whiteleaf7 (original)", "Rumia-Channel (fork from)", "ponponusa (mod maintainer)"]
  gem.email         = ["init0531.usa@gmail.com"]
  gem.homepage      = "https://github.com/ponponusa/narou-mod"
  gem.summary       = "Narou.rb MOD ― 小説家になろうダウンローダ＆縦書用整形スクリプト"
  gem.description   = "小説家になろうで公開されている小説を管理し電子書籍データへ変換します。"
  install_message   = <<~MSG
    ============================================================
     Narou.rb_MOD v#{::Narou::VERSION} がインストールされました 🎉

      コマンドヘルプ　　　:  narou-mod --help
      初期設定　　　　　　:  narou-mod init #既に存在するDBは上書きされません
      小説の追加　　　　　:  narou-mod add <小説ID>
      小説ダウンロード　　:  narou-mod download <小説ID>
      Ｗｅｂサーバー起動　:  narou-mod web

     更新情報: https://github.com/ponponusa/narou/releases
    ============================================================
  MSG
  gem.post_install_message = install_message.gsub("\t", "  ")

  gem.required_ruby_version = ">=3.4.0"

  tracked_files = `git ls-files`.split("\n").select { |fn| File.exist?(fn) }
  gem.files = tracked_files.reject { |fn| fn =~ %r!^spec/|^"spec! } << Narou.create_git_commit_version

  # フロントエンドのビルド成果物を追加（git管理外でも含める）
  frontend_dist = Dir.glob("frontend/dist/**/*").select { |f| File.file?(f) }
  gem.files += frontend_dist if Dir.exist?("frontend/dist")

  gem.executables = gem.files.grep(%r!^bin/!).map { |f| File.basename(f) }

  gem.add_runtime_dependency 'termcolorlight', '~> 1.0', '>= 1.1.1'
  gem.add_runtime_dependency 'rubyzip', '~> 3.2', '>= 3.2.0'
  gem.add_runtime_dependency 'mail', '~> 2.9', '>= 2.9.0'
  gem.add_runtime_dependency 'pony', '~> 1', '>= 1.13'
  gem.add_runtime_dependency 'diff-lcs', '~> 1.6', '>= 1.6.2'
  gem.add_runtime_dependency 'sinatra', '~> 4.2', '>= 4.2.0'
  gem.add_runtime_dependency 'sinatra-contrib', '~> 4.2', '>= 4.2.0'
  gem.add_runtime_dependency 'rackup', '~> 2.1'
  gem.add_runtime_dependency 'rack', '>= 3.0', '< 4'
  gem.add_runtime_dependency 'rack-session', '~> 2.1', '>= 2.1.1'
  gem.add_runtime_dependency 'puma', '~> 6.4'
  gem.add_runtime_dependency 'sass-embedded', '~> 1.93', '>= 1.93.2'
  gem.add_runtime_dependency 'tilt', '~> 2.6', '>= 2.6.1'
  gem.add_runtime_dependency 'ffi', '~> 1.17', '>= 1.17.2'
  gem.add_runtime_dependency 'haml', '>= 5.2.2', '< 6'
  gem.add_runtime_dependency 'memoist', '~> 0.16.2'
  gem.add_runtime_dependency 'systemu', '~> 2.6', '>= 2.6.5'
  gem.add_runtime_dependency 'erubi', '~> 1.13.1'
  gem.add_runtime_dependency 'open_uri_redirections', '~> 0.2', '>= 0.2.1'
  gem.add_runtime_dependency 'activesupport', '~> 8.0', '>= 8.1.0'
  gem.add_runtime_dependency 'unicode-display_width', '>= 1.5', '< 3.0'
  gem.add_runtime_dependency 'nokogiri', '~> 1.18'
  gem.add_runtime_dependency 'fiddle', '~> 1.0'

  # TUI libraries for enhanced CLI user experience
  gem.add_runtime_dependency 'tty-markdown', '~> 0.7'
  gem.add_runtime_dependency 'tty-spinner', '~> 0.9'
  gem.add_runtime_dependency 'tty-box', '~> 0.7'
  gem.add_runtime_dependency 'tty-prompt', '~> 0.23'
  gem.add_runtime_dependency 'psych', '~> 5.2'
  gem.add_runtime_dependency 'nkf', '~> 0.2.0'
  gem.add_runtime_dependency 'csv', '~> 3.3'
  gem.add_runtime_dependency 'rexml', '~> 3.4'
  gem.add_runtime_dependency 'ostruct', '~> 0.6.3'
  # Ruby 3.5+ で default gem から外れるため明示的に追加
  gem.add_runtime_dependency 'win32ole', '~> 1.9'    # Windows 専用（他OSでは無視される）
  gem.add_runtime_dependency 'bootsnap', '~> 1.18', '>= 1.18.6'  # Unix系で高速化（Windowsでは無視される）

  gem.add_development_dependency 'rspec', '~> 3.13'
  gem.add_development_dependency 'rspec-retry', '~> 0.6'
  gem.add_development_dependency 'rspec_junit_formatter', '~> 0.6'
  gem.add_development_dependency 'rubocop', '~> 1.81', '>= 1.81.6'
  gem.add_development_dependency 'timecop', '~> 0.9'
  gem.add_development_dependency 'pry', '~> 0.15'
  gem.add_development_dependency 'pry-byebug', '~> 3.11'
  gem.add_development_dependency 'awesome_print', '~> 1.9'
  gem.add_development_dependency 'simplecov', '~> 0.22'
  gem.add_development_dependency 'rack-test', '~> 2.1'
end
