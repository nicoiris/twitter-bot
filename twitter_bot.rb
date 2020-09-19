require 'natto'
require 'twitter'

class TweetBot
  attr_accessor :client
  attr_accessor :screen_name

  public
    def initialize(screen_name)
      #twitterのデベロッパーサイトより申請して取得
      @client = Twitter::REST::Client.new do |config|
        config.consumer_key = "*****************"
        config.consumer_secret = "****************"
        config.access_token = "****************"
        config.access_token_secret = "****************"
      end
  
      @screen_name = screen_name
    end
     
    def post(text)
      @client.update(text)
    end
    
    def get_tweet(count, user=@screen_name)
      tweets = []
      # user_timelineで取得できる制限が200件のため、200件のツイートを取得
        @client.user_timeline(user, {count: count}).each do |timeline|
          tweet = @client.status(timeline.id)
          # RT(とRTを含むツイート)を除外
          if not (tweet.text.include?("RT"))
            # TweetDeckとiphone公式以外からのツイートを除外
            if (tweet.source.include?("TweetDeck") or
                tweet.source.include?("Twitter for iPhone"))
              # 該当ツイートからリプライとURLを除いたものをtweets配列に追加
              tweets.push(tweet2textdata(tweet.text))
            end
          end
        end
      # end

      return tweets
    end
        

class NattoParser
  attr_accessor :nm
  
  def initialize()
    #neologd辞書を使用
    @nm = Natto::MeCab.new("-d /usr/local/lib/mecab/dic/mecab-ipadic-neologd")
  end
  
  # textsには取得した約200件のツイートが渡されている
  def parseTextArray(texts)
    words = []
    index = 0

    for text in texts do
      # 単語数を数える
      count_noun = 0
      # textに渡された文字列を形態素解析
      @nm.parse(text) do |n|
        count_noun += 1
      end

      # 渡された文字列の単語が1単語しかなければ以後の処理を行わない
      if count_noun == 1
        next
      end

      words.push(Array[])
      @nm.parse(text) do |n|
        if n.surface != ""
          words[index].push([n.surface, n.posid])
        end
      end
      index += 1
    end

    return words
  end
end

class Marcov
  public
    def marcov(array)
      result = []
      block = []
      
      # 先頭が-1（つまり文頭の塊）の配列のみを取り出して配列にまとめてblockに代入
      block = findBlocks(array, -1)
      #begin ~ rescueで例外処理
      begin
        # 文頭の候補からランダムに選ばれたものをresult配列に追加
        result = connectBlocks(block, result)
        if result == -1
          raise RuntimeError
        end
      rescue RuntimeError
        retry
      end
     
      # resultの最後の単語が-1になるまで繰り返す
      while result[result.length-1] != -1 do
        # 現時点でresultに入っている最後の単語を頭に持つ単語の配列の候補を全てblockに代入
        # 例えば resultが[-1 , 今日 , は]という配列なら、「は」から始まる3単語の配列を探す
        block = findBlocks(array, result[result.length-1])
        # 候補の配列が見つからなかった場合もしかしたら無限ループするかも 要検証
        begin
          result = connectBlocks(block, result)
          if result == -1
            raise RuntimeError
          end
        rescue RuntimeError
          return -1
        end
      end
      
      return result
    end

    def genMarcovBlock(words)
      array = []

      # 最初と最後は-1にする(文頭と文末を判別するため)
      words.unshift(-1)
      words.push(-1)

      # 3単語ずつ配列に格納
      for i in 0..words.length-3
        array.push([words[i], words[i+1], words[i+2]])
      end

      return array
    end

  private
    def findBlocks(array, target)
      blocks = []
      for block in array
        if block[0] == target
          blocks.push(block)
        end
      end
      
      return blocks
    end

    def connectBlocks(array, dist)
      i = 0
      begin
        # 候補である3単語の配列をランダムに選ぶ
        for word in array[rand(array.length)]
          # 3単語のうち頭を除いた2単語を追加 
          if i != 0
            dist.push(word)
          end
          i += 1
        end
      rescue NoMethodError
        return -1
      else
        return dist
      end
    end
end

# ===================================================
# 汎用関数
# ===================================================
def generate_text(bot, screen_name=nil, dir=nil)
  parser = NattoParser.new
  marcov = Marcov.new

  block = []

  tweet = ""
  
  # ツイートを持ってくるユーザー名が入っているか
  if not screen_name == nil
    # 最新200件のツイートをget_tweetメソッドに基づいて取得
    tweets = bot.get_tweet(200, screen_name)
  else
    raise RuntimeError
  end
  # 形態素解析を行い単語ごとに分解
  words = parser.parseTextArray(tweets)
  # 3単語ブロックをツイートごとの配列に格納
  for word in words
    block.push(marcov.genMarcovBlock(word))
  end

  block = reduce_degree(block)

  # 140字に収まる文章が練成できるまでマルコフ連鎖する
  while tweet.length == 0 or tweet.length > 140 do
    # begin ~ rescueで例外処理
    begin
      tweetwords = marcov.marcov(block)
      if tweetwords == -1
        raise RuntimeError
      end
    rescue RuntimeError
      retry
    end
    # 出来上がった文章のうち品詞IDを取り除く
    tweet = words2str(tweetwords)
  end
  
  return tweet
end

def words2str(words)
  str = ""
  for word in words do
    if word != -1
      str += word[0]
    end
  end
  return str
end

def reduce_degree(array)
  result = []
  # 3単語ずつの単語と品詞IDが入った配列をresultに渡す（次元削減）
    array.each do |a|
    a.each do |v|
      result.push(v)
    end
  end
  
  return result
end

def tweet2textdata(text)
  # リプライを抽出して除外
  replypattern = /@[\w]+/
  text = text.gsub(replypattern, '')

  # URLを含むツイートのURLの部分のみを削除（無に置き換え）
  textURI = URI.extract(text)
  for uri in textURI do
    text = text.gsub(uri, '')
  end 

  return text
end
# ===================================================
# MAIN
# ===================================================
def main()
  bot = TweetBot.new("bot_id")
  
  tweet_source = "twitter_id"

  tweet = generate_text(bot, tweet_source)

  p tweet

  bot.post(tweet)
  
end

main()