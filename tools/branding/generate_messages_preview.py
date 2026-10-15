"""Messages palette and composition proof. This does not render the iOS application.

Reference study: GetStream/SwiftUIMessagesUIClone, GetStream/swiftui-iMessage-clone,
exyte/Chat, MessageKit/MessageKit, unionst/swift-chat, InputBarAccessoryView and ChatLayout.
The proof reads our production palette. Artwork and rendering below are original.
"""
import argparse
from pathlib import Path
import re
from PIL import Image, ImageDraw, ImageFont
from generate_icons import render

ROOT = Path(__file__).resolve().parents[2]


def generate(output):
    factory = (ROOT/'submodules/TelegramPresentationData/Sources/MakePresentationTheme.swift').read_text(encoding='utf-8')
    tokens = {name: ('#'+dark[2:], '#'+light[2:]) for name, dark, light in re.findall(r'let (\w+) = UIColor\(rgb: messages && dark \? (0x[0-9A-F]+) : messages \? (0x[0-9A-F]+)', factory)}
    canvas = Image.new('RGB',(1680,1080),'#E6E8EC')
    d = ImageDraw.Draw(canvas)
    fonts = [Path('C:/Windows/Fonts/segoeui.ttf'),Path('/System/Library/Fonts/Supplemental/Arial.ttf'),Path('/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf')]
    font = next((str(p) for p in fonts if p.exists()),None)
    def text(x,y,value,size=17,color='#1C1C1E'):
        f = ImageFont.truetype(font,size) if font else ImageFont.load_default(size=size)
        d.text((x,y),value,font=f,fill=color)
    text(52,30,'BananaGram · Messages',38)
    text(54,87,'Светлая и тёмная темы · список чатов · переписка',22,'#5C5C62')
    for col,mode,chat in [(0,1,False),(1,1,True),(2,0,False),(3,0,True)]:
        x=52+col*400;y=158;w=376;h=790
        c={name:pair[mode] for name,pair in tokens.items()}
        bg='#FFFFFF' if mode else '#000000'
        d.rounded_rectangle((x-2,y-2,x+w+2,y+h+2),radius=37,fill='#A7A9AE')
        d.rectangle((x,y,x+w,y+h),fill=bg)
        text(x+22,y+14,'9:41',15,c['foreground'])
        for bar in range(3):
            d.rounded_rectangle((x+w-64+bar*5,y+25-bar*3,x+w-61+bar*5,y+29),radius=1,fill=c['foreground'])
        d.rounded_rectangle((x+w-41,y+19,x+w-21,y+29),radius=3,outline=c['foreground'])
        d.rectangle((x+w-38,y+22,x+w-25,y+26),fill=c['foreground'])
        text(x+112,y+52,'Анна' if chat else 'Сообщения',21,c['foreground'])
        text(x+20,y+50,'‹' if chat else '•••',24,c['accent'])
        if chat:
            text(x+w-42,y+52,'›',23,c['accent'])
        else:
            d.rounded_rectangle((x+w-43,y+57,x+w-25,y+75),radius=3,outline=c['accent'],width=2)
            d.line((x+w-38,y+69,x+w-21,y+52),fill=c['accent'],width=3)
        if not chat:
            d.rounded_rectangle((x+15,y+99,x+w-15,y+137),radius=12,fill=c['searchBar'])
            d.ellipse((x+29,y+110,x+39,y+120),outline=c['secondary'],width=2)
            d.line((x+38,y+119,x+43,y+124),fill=c['secondary'],width=2)
            text(x+52,y+105,'Поиск',17,c['secondary'])
            rows=[('АН','Анна','Увидимся вечером?','Скину фотографии чуть позже.','10:42',True),('МК','Максим','Спасибо, всё получилось!','','09:18',True),('Д','Дизайн','Обновили макеты приложения','Можно посмотреть новую тему.','Вчера',False),('ОЛ','Ольга','Голосовое сообщение','','Вчера',False),('К','Команда','Альбом: 4 фотографии','','Вт',False),('П','Павел','Отлично, договорились','','Пн',False)]
            for i,(initials,name,line1,line2,date,unread) in enumerate(rows):
                top=y+166+i*87
                if unread:d.ellipse((x+11,top+24,x+20,top+33),fill=c['accent'])
                d.ellipse((x+27,top+4,x+77,top+54),fill=['#588DA8','#977CA4','#6C9B82'][i%3])
                text(x+35,top+17,initials,15,'#FFFFFF')
                text(x+88,top,name,17,c['foreground'])
                text(x+w-76,top+1,date,12,c['secondary'])
                text(x+w-21,top,'›',18,c['disclosure'])
                text(x+88,top+27,line1,14,c['secondary'])
                if line2:text(x+88,top+47,line2,14,c['secondary'])
                d.line((x+88,top+78,x+w,top+78),fill=c['separator'],width=1)
        else:
            text(x+144,y+80,'в сети',12,c['secondary'])
            text(x+137,y+121,'Сегодня, 10:42',12,c['secondary'])
            # The final bubble of a sender group gets the native curved tail.
            for bx,by,bw,bh,outgoing,lines,tail in [(x+15,y+171,260,61,False,['Увидимся вечером?'],False),(x+15,y+235,284,80,False,['Скину фотографии','чуть позже.'],True),(x+109,y+352,251,92,True,['Да, буду к семи.','Возьму что-нибудь к чаю.'],True)]:
                fill='#0064CF' if outgoing else c['raisedSurface'];fg='#FFFFFF' if outgoing else c['foreground']
                d.rounded_rectangle((bx,by,bx+bw,by+bh),radius=20,fill=fill)
                if tail:
                    points=[(bx+bw-20,by+bh-24),(bx+bw+5,by+bh),(bx+bw-23,by+bh-4)] if outgoing else [(bx+20,by+bh-24),(bx-5,by+bh),(bx+23,by+bh-4)]
                    d.polygon(points,fill=fill)
                for i,line in enumerate(lines):text(bx+14,by+11+i*23,line,15,fg)
                text(bx+bw-51,by+bh-19,'10:42',10,fg if outgoing else c['secondary'])
            d.rounded_rectangle((x+220,y+450,x+301,y+480),radius=15,fill=c['raisedSurface'])
            text(x+233,y+453,'♥  1',16,c['foreground'])
            # Media uses the same rounded geometry and theme-aware controls.
            px=x+15;py=y+526
            d.rounded_rectangle((px,py,px+244,py+115),radius=20,fill='#A2C5D8')
            d.polygon([(px+1,py+93),(px+71,py+31),(px+133,py+92),(px+177,py+48),(px+243,py+96),(px+243,py+114),(px+1,py+114)],fill='#648E88')
            d.ellipse((px+183,py+17,px+212,py+46),fill='#FFF1C6')
            media=canvas.crop((px,py,px+244,py+115));media_mask=Image.new('L',(244,115));ImageDraw.Draw(media_mask).rounded_rectangle((0,0,243,114),radius=20,fill=255)
            d.rectangle((px,py,px+244,py+115),fill=bg);canvas.paste(media,(px,py),media_mask)
            d.rectangle((x,y+h-76,x+w,y+h),fill=c['surface'])
            d.ellipse((x+13,y+h-62,x+53,y+h-22),fill=c['searchBar'])
            text(x+25,y+h-62,'+',26,c['foreground'])
            d.rounded_rectangle((x+65,y+h-62,x+w-65,y+h-22),radius=20,fill=c['searchBar'],outline=c['separator'])
            text(x+80,y+h-54,'Сообщение',16,c['secondary'])
            d.ellipse((x+w-53,y+h-62,x+w-13,y+h-22),fill='#0064CF')
            text(x+w-42,y+h-61,'↑',26,'#FFFFFF')
        crop=canvas.crop((x,y,x+w,y+h));mask=Image.new('L',(w,h));ImageDraw.Draw(mask).rounded_rectangle((0,0,w-1,h-1),radius=36,fill=255)
        d.rectangle((x,y,x+w,y+h),fill='#E6E8EC');canvas.paste(crop,(x,y),mask)
    text(54,976,'Макет палитры и компоновки. Это не скриншоты приложения.',18,'#5C5C62')
    icon=render('MessagesIcon',(64,64));mask=Image.new('L',(64,64));ImageDraw.Draw(mask).rounded_rectangle((0,0,63,63),radius=14,fill=255);canvas.paste(icon,(1490,978),mask)
    text(1565,997,'Messages',15,'#5C5C62')
    output.parent.mkdir(parents=True,exist_ok=True);canvas.save(output,optimize=True)
    print(output)


if __name__=='__main__':
    parser=argparse.ArgumentParser();parser.add_argument('--output',type=Path,default=ROOT/'assets/branding/MessagesPreview.png')
    generate(parser.parse_args().output)
