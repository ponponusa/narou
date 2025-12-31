# frozen_string_literal: true

# テスト時に$stdoutへの出力を抑制するヘルパー
RSpec.configure do |config|
  config.around(:each) do |example|
    # show_outputメタデータがある場合は出力を抑制しない
    if example.metadata[:show_output]
      example.run
    else
      # テスト中は$stdoutをStringIOにリダイレクトして出力を抑制
      original_stdout = $stdout
      begin
        $stdout = StringIO.new
        example.run
      ensure
        $stdout = original_stdout
      end
    end
  end
end
