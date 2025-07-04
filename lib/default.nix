{ pkgs }:

with pkgs.lib; {
  # Add your library functions here
  #
  # hexint = x: hexvals.${toLower x};
  # 把 lonerOrz 加到 lib.maintainers 里
  maintainers = maintainers // {
    lonerOrz = {
      name   = "lonerOrz";
      email  = "lonerOrz@qq.com";
      github = "lonerOrz";
    };
  };
}
