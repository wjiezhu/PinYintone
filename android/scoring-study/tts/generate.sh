#!/bin/zsh
# 用 macOS `say` 生成实验用 TTS 音频（16-bit PCM / 单声道 / 16 kHz），输出到 build/tts/。
# 参考：Tingting @140 wpm（近似 iOS AVSpeechUtterance.rate = 0.4 的 zh-CN 默认语音）。
# 「学习者」侧：多个中文语音 × 三种语速，读每个词（作正确读法，也作其它目标词的错调读法）。
# 用法：android/scoring-study/tts/generate.sh   （只在 macOS 上能跑；结果不入库，可随时重建）
set -e
here=${0:A:h}
out=$here/../build/tts
mkdir -p $out/ref $out/learner
words=$(grep -v '^#' $here/words.tsv | cut -f1)
tmp=$(mktemp -d)
# `say` 偶尔会卡死在某个词上：每次最多 20 秒，超时就跳过该文件（实验按缺失处理）
say_to() { rm -f $tmp/a.aiff; perl -e 'alarm 20; exec @ARGV' say "$@" -o $tmp/a.aiff || true; }
for w in ${(f)words}; do
  f=$out/ref/Tingting_140_$w.wav
  [[ -f $f ]] || { say_to -v Tingting -r 140 "$w"; [[ -s $tmp/a.aiff ]] && afconvert -f WAVE -d LEI16@16000 -c 1 $tmp/a.aiff $f || echo "skip $f"; }
done
for v in Tingting Eddy Flo Reed Sandy Shelley Grandma Grandpa Rocko; do
  vv=$v; [[ $v != Tingting ]] && vv="$v (Chinese (China mainland))"
  for r in 110 175 260; do
    for w in ${(f)words}; do
      f=$out/learner/${v}_${r}_$w.wav
      [[ -f $f ]] || { say_to -v "$vv" -r $r "$w"; [[ -s $tmp/a.aiff ]] && afconvert -f WAVE -d LEI16@16000 -c 1 $tmp/a.aiff $f || echo "skip $f"; }
    done
  done
done
rm -rf $tmp
echo "done: $(ls $out/ref | wc -l) ref, $(ls $out/learner | wc -l) learner"
