# blog

> 个人博客

## 部署

### GitHub

提交代码到 `hugo` 分支即可触发 `GitHub Action`，自动发布部署，部署在 GitHub 提供的 page 上，编译后代码在 `gh-pages` 分支。

### 阿里云（国内已备案）

使用的轻量云服务器（docker 环境），由于证书问题，不在线上自动化打包，需要本地打包再提到阿里云服务上运行。

步骤：

- 本地证书（该证书不会提交到 git）放到根目录
- `make docker-build v=latest`
- 本地运行 docker 镜像测试查看
- `make docker-push v=latest`
- 登录服务器更新容器

或：

`make docker-release v=latest` 一键部署，但是确保机器有登录权限
