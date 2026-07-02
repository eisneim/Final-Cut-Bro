

1.素材预览skimming的 红色cursor应该只有一条的高度，而不是两层高度；
2.增加bash tool，比如我要实现：把时间轴上吗的素材，没有说话的安静的地方减掉，那么Agent可以bash FFMPEG获得音频的level，并做分析用python做数据分析，然后得到区间，然后再剪辑； bash要对高危操作拦截让用户确认，普通的命令不用拦截，比如python， FFMPEG等等，rm rf之类的拦截；