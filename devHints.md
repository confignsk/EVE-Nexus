# 列表中第一项sheet总是为空

使用单独的行管理器视图，参考v1.6.1的ImplantPresetView.swift改动

# iOS 17中，含有 textfield 的 .alert 不符合深色模式设计

iOS 17 问题，通过自定义包装修改

iOS 17 问题很多

# 去除敏感内容如key

## 安装BFG
brew install bfg

## 创建包含要替换文本的文件
echo "xxxx" > secrets.txt

## 从历史记录中替换密钥
bfg --replace-text secrets.txt
