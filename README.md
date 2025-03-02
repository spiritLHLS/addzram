# addzram

更新时间：2025.03.02

为linux服务器启用zram设备(压缩内存)

```bash
curl -L https://raw.githubusercontent.com/spiritLHLS/addzram/main/addzram.sh -o addzram.sh && chmod +x addzram.sh && bash addzram.sh
```

类同之前的

https://github.com/spiritLHLS/addswap

同样是给机器优化内存占用的东西，只不过zram是压缩内存占用，swap是附加虚拟内存增加内存空间，二者都会占用CPU资源，zram在CPU性能冗余的机器上使用更优

(理论上zram会比swap的性能占用低，但未实际测试过)

### 单位换算：输入 1024 产生 1G 的 zram 设备压缩内存，zram 设备大小最好不要大于实际内存大小

# 致谢

感谢 [@Ella-Alinda](https://github.com/Ella-Alinda) 提供优化建议
