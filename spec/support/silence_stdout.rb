# frozen_string_literal: true

# テスト時に$stdoutへの出力を抑制するヘルパー
RSpec.configure do |config|
  config.around(:each) do |example|
    # show_outputメタデータがある場合、または$stdout.captureを使うテストの場合は出力を抑制しない
    if example.metadata[:show_output] || example.metadata[:use_capture]
      example.run
      next
    end
    
    # テスト中は$stdoutをStringIOにリダイレクトして出力を抑制
    original_stdout = $stdout
    $stdout = StringIO.new
    
    example.run
  ensure
    $stdout = original_stdout
  end
end
