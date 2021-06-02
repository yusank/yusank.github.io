---
title: "Go Image"
date: 2017-08-22T12:20:00+08:00
update: 2017-08-23T12:18:00+08:00
categories:
- 技术
tags:
- go
- 图片处理
---

用 GO 实现图片处理和文字合成

# Go 的图片处理

最近需要一个合成明信片的工具，即往背景图的固定位置上添加一个图片和一段文字， 最后合成一张图片。由于是 go 程序的一个子功能，所以我想我只加拿 go 写好了，正好有 go 的 `image` 库，拿来练练。

## 图片合成

图片合成我用到了这个库  `github.com/disintegration/imaging`

代码：

``` go
package main

import (
    "fmt"
    "image"

    "github.com/disintegration/imaging"
)

func HandleUserImage(fileName string) (string, error) {
	m, err := imaging.Open("target.jpg")
	if err != nil {
		fmt.Printf("open file failed")
	}

	bm, err := imaging.Open("bg.jpg")
	if err != nil {
		fmt.Printf("open file failed")
	}

	// 图片按比例缩放
	dst := imaging.Resize(m, 200, 200, imaging.Lanczos)
	// 将图片粘贴到背景图的固定位置
	result := imaging.Overlay(bm, dst, image.Pt(120, 140), 1)

	fileName := fmt.Sprintf("%d.jpg", fileName)
	err = imaging.Save(result, fileName)
	if err != nil {
		return "", err
	}

	return fileName, nil
}
```

以上是将 `target.jpg` 文件先进行缩放，再贴到 `bg.jpg` 文件的 （120，140）位置，最后保存成文件。

## 图片上写文字

以下是写文字和贴图的一块用的实例：

``` go
package main

import (
	"fmt"
	"image"
	"image/color"
	"io/ioutil"

	"github.com/disintegration/imaging"
	"github.com/golang/freetype"
	"github.com/golang/freetype/truetype"
	"golang.org/x/image/font"
)

func main() {
	HandleUserImage()
}

// HandleUserImage paste user image onto background
func HandleUserImage() (string, error) {
	m, err := imaging.Open("target.png")
	if err != nil {
		fmt.Printf("open file failed")
	}

	bm, err := imaging.Open("bg.jpg")
	if err != nil {
		fmt.Printf("open file failed")
	}

	// 图片按比例缩放
	dst := imaging.Resize(m, 200, 200, imaging.Lanczos)
	// 将图片粘贴到背景图的固定位置
	result := imaging.Overlay(bm, dst, image.Pt(120, 140), 1)
	writeOnImage(result)

	fileName := fmt.Sprintf("%d.jpg", 1234)
	err = imaging.Save(result, fileName)
	if err != nil {
		return "", err
	}

	return fileName, nil
}

var dpi = flag.Float64("dpi", 256, "screen resolution")

func writeOnImage(target *image.NRGBA) {
	c := freetype.NewContext()

	c.SetDPI(*dpi)
	c.SetClip(target.Bounds())
	c.SetDst(target)
	c.SetHinting(font.HintingFull)

        // 设置文字颜色、字体、字大小
	c.SetSrc(image.NewUniform(color.RGBA{R: 240, G: 240, B: 245, A: 180}))
	c.SetFontSize(16)
	fontFam, err := getFontFamily()
	if err != nil {
		fmt.Println("get font family error")
	}
	c.SetFont(fontFam)

	pt := freetype.Pt(500, 400)

	_, err = c.DrawString("我是水印", pt)
	if err != nil {
		fmt.Printf("draw error: %v \n", err)
	}

}

func getFontFamily() (*truetype.Font, error) {
        // 这里需要读取中文字体，否则中文文字会变成方格
	fontBytes, err := ioutil.ReadFile("Hei.ttc")
	if err != nil {
		fmt.Println("read file error:", err)
		return &truetype.Font{}, err
	}

	f, err := freetype.ParseFont(fontBytes)
	if err != nil {
		fmt.Println("parse font error:", err)
		return &truetype.Font{}, err
	}

	return f, err
```

最后来一张效果图
![](http://oid1xlj7h.bkt.clouddn.com/image/jpg/1234.jpg)

## 总结

做的过程中，合作这一块比较好做，但是图片上写文字，相对比较麻烦，而且 `freetype` 库并没有默认的中英文字体，如果不指定字体会报错，而且字体格式只限制于 `ttf` 和 `ttc` 两种。
