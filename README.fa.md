<div dir="rtl">

# هسته Xray «patterniha» برای PassWall2 (OpenWrt)

[English](README.md) | [فارسی](README.fa.md)

## ❤️ تشکر ویژه از patterniha

**همه اعتبار این هسته متعلق به [patterniha](https://github.com/patterniha) است.**
او هسته سفارشی Xray ([patterniha/xray-core](https://github.com/patterniha/xray-core)) و کلاینت‌هایش را می‌سازد و نگه می‌دارد:
[PattN](https://github.com/patterniha/PattN) (دسکتاپ) و [PattNG](https://github.com/patterniha/PattNG) (اندروید).
این ریپو **هیچ کدی از او ندارد** و فقط یک نصب‌کننده کوچک است که ریلیز رسمی او را دانلود می‌کند و روی OpenWrt اجرا می‌کند.
لطفاً از پروژه‌هایش حمایت کنید و ستاره بدهید.

> ⚠️ **این اسکریپت کاملاً وایب‌کد شده است** (با دستیار هوش مصنوعی نوشته شده). فقط روی یک ماشین مجازی x86_64 با OpenWrt 25.12 تست شده.
> قبل از اجرا با دسترسی root آن را بخوانید و با مسئولیت خودتان استفاده کنید.

## این چیست

بازنویسی Xray نیست. `pattx` یک اسکریپت شل حدود ۲۰۰ خطی است که:

- معماری روتر را تشخیص می‌دهد (x86، arm، mips، mipsel، riscv64، loong64 و ...)
- ریلیز رسمی مناسب را از `patterniha/xray-core` می‌گیرد و SHA-256 را بررسی می‌کند
- آن را در `/opt/pattx` با سرویس procd نصب می‌کند (اجرا با بوت و ری‌استارت خودکار)
- در صورت تمایل **PassWall2** را به‌جای xray استاندارد روی این هسته می‌برد
- آپدیت و بازگشت به نسخه قبل را با یک دستور انجام می‌دهد

هسته همان هسته PattN و PattNG است، پس قابلیت‌های اضافه‌ای که او به هسته داده از طریق کانفیگ JSON معمولی Xray روی روتر هم در دسترس است.

## نصب

روی روتر (نیاز به اینترنت و دسترسی به GitHub؛ `curl` یا `wget`؛ اگر `unzip` نبود خودکار نصب می‌شود):

```sh
wget -O /tmp/pattx.sh https://raw.githubusercontent.com/moein8668-git/patterniha-xray-for-passwall2/main/pattx.sh
sh /tmp/pattx.sh install
```

یا از ویندوز (SSH با root به روتر):

```powershell
.\install.ps1 -Router 192.168.1.1
```

نتیجه پیش‌فرض: SOCKS5 روی `:10808` (با UDP)، HTTP روی `:10809`، بدون احراز هویت (اگر روتر در دسترس بیرون است به LAN محدودش کنید).

## دستورها

```
pattx update               آپدیت به آخرین ریلیز (اگر همان باشد کاری نمی‌کند)
pattx update v26.10.9      نصب نسخه مشخص
pattx rollback             برگشت به هسته قبلی
pattx status               ورژن، سرویس، پورت‌ها، مسیر PassWall2
pattx passwall on|off      استفاده در PassWall2 / برگشت به xray استاندارد
pattx ech                  DNS نودهای ECH در PassWall2 را direct می‌کند (خودکار هم انجام می‌شود)
pattx dns                  نمایش Remote DNS پس‌وال و هشدار اگر tcp باشد
pattx dns udp [IP] [-y]    تغییر Remote DNS به UDP (هشدار، سؤال، بررسی، برگشت خودکار در صورت خرابی)
pattx dns restore          برگرداندن آخرین تغییر `pattx dns udp`
pattx auto on [HH:MM]      هر روز در ساعت داده‌شده (به وقت روتر) خودکار 'pattx update' را اجرا می‌کند (پیش‌فرض ۰۴:۱۷، مثال: 'pattx auto on 03:30')؛ پیش‌فرض خاموش
pattx auto off             خاموش کردن آپدیت روزانه (ساعت یعنی ساعت خود روتر: با `date` ببینید؛ OpenWrt پیش‌فرض UTC است مگر در System > General منطقه زمانی را تنظیم کنید)
pattx uninstall
```

## پروکسی محلی مستقل

کانفیگ JSON خودتان را در `/opt/pattx/config.json` بگذارید، بعد:

```sh
/opt/pattx/xray run -test -c /opt/pattx/config.json && /etc/init.d/pattx restart
```

## استفاده در PassWall2

```sh
pattx passwall on     # مسیر xray در PassWall2 را روی /opt/pattx/xray می‌گذارد
```

**شیم سازگاری (فقط برای PassWall2 قدیمی‌تر از 26.10):** هسته‌های جدید Xray (از جمله این یکی) فیلد `proxySettings` را از outbound حذف کرده‌اند
(جایگزین: `streamSettings.sockopt.dialerProxy`) ولی PassWall2 نسخه 26.8.x هنوز آن را می‌نویسد، برای همین هسته بالا نمی‌آید
(وضعیت «Core NOT RUNNING»). دستور `pattx passwall on` یک شیم کوچک به `/usr/lib/lua/luci/passwall2/util_xray.lua` اضافه می‌کند
که این فیلد را تبدیل می‌کند؛ `pattx passwall off` و `uninstall` فایل اصلی را برمی‌گردانند (نسخه پشتیبان: `util_xray.lua.pattx.bak`).
آپگرید PassWall2 فایل را بازنویسی می‌کند، پس بعدش دوباره `pattx passwall on` (یا `pattx update`) بزنید.
PassWall2 نسخه 26.10.1 به بعد خودش از `dialerProxy` استفاده می‌کند و شیم خودکار رد می‌شود (روی 26.10.1 تست شده).

PassWall2 کانفیگ را خودش می‌سازد؛ فیلدی که فقط در هسته patterniha هست باید در ویرایشگر نود PassWall2 پذیرفته شود.
دکمه «آپدیت Xray» خود PassWall2 را نزنید چون هسته را عوض می‌کند. به‌جایش `pattx update` بزنید.

## نودهای ECH (خودکار)

نودهای ECH (مثل `echConfigList: cloudflare-ech.com+udp://8.8.8.8`) باعث می‌شوند هسته رکورد ECH را از آن DNS بگیرد.
روی روتر این کوئری از خود روتر خارج می‌شود و پروکسی شفاف PassWall2 آن را به همان نود می‌فرستد، در حالی که نود برای وصل شدن به ECH نیاز دارد: یک حلقه
(خطای `Failed to query ECH DNS record ... i/o timeout` در لاگ xray پس‌وال).

`pattx` این را خودکار حل می‌کند: دستور `pattx ech` سرور DNS مربوط به ECH هر نود PassWall2 را می‌خواند و به لیست Direct IP پس‌وال
(`/usr/share/passwall2/direct_ip`) اضافه می‌کند و اگر چیزی عوض شد PassWall2 را ری‌استارت می‌کند. خودش اجرا می‌شود:
- وقتی در LuCI تنظیمات PassWall2 را ذخیره/اعمال می‌کنید (تریگر `config.change` در procd، پس نودهای ECH جدید هم پوشش داده می‌شوند)
- هنگام بالا آمدن سرویس `pattx` (بوت) و با `pattx install` / `pattx update` / `pattx passwall on`

نکته: آپگرید پکیج PassWall2 فایل `direct_ip` را بازنویسی می‌کند؛ بعدش `pattx ech` (یا `pattx update`) بزنید.
اگر در `ech_config` اسم دامنه باشد (مثل `https://dns.google/dns-query`) هنگام همگام‌سازی resolve می‌شود و IPv4هایش اضافه می‌شوند.

## «تست نود OK است ولی ترافیکی از روتر رد نمی‌شود»: Remote DNS (از شما می‌پرسد)

دو مشکل DNS کاملاً جدا وجود دارد و `pattx` با هرکدام فرق می‌کند:

| | DNS مربوط به ECH (بخش بالا) | Remote DNS (این بخش) |
|---|---|---|
| چه کسی می‌پرسد | خود هسته، برای گرفتن کلید ECH قبل از وصل شدن به نود | PassWall2، برای resolve کردن سایت‌هایی که دستگاه‌ها باز می‌کنند |
| علامت | `Failed to query ECH DNS record ... i/o timeout`، نود اصلاً وصل نمی‌شود | نود وصل است و «تست» OK می‌دهد ولی هیچ سایتی باز نمی‌شود؛ در لاگ `app/dns: failed to read response length > EOF` (یا `closed pipe`) |
| علت | کوئری به پروکسی شفاف می‌رسد و به همان نود می‌رود: حلقه | بسیاری از نودهای پشت CDN (مثل Cloudflare) **TCP/53** را می‌بندند و Remote DNS پیش‌فرض PassWall2 برابر `tcp://1.1.1.1` است |
| کار pattx | **خودکار** (`pattx ech`) | **از شما می‌پرسد** (`pattx dns udp`): هشدار، `y/N`، بررسی، برگشت خودکار |

چرا «تست نود» با این حال OK می‌دهد: تست از SOCKS با resolve سمت سرور استفاده می‌کند، یعنی خود نود اسم را resolve می‌کند و DNS روتر دخالت ندارد.
حالت شفاف اول باید روتر اسم را resolve کند. بدون Remote DNS سالم حتی `pattx update` هم به GitHub نمی‌رسد.

```sh
pattx dns                  # نمایش Remote DNS فعلی، هشدار اگر tcp باشد
pattx dns udp              # تغییر به UDP (اگر IP فعلی IPv4 باشد نگه داشته می‌شود وگرنه 8.8.8.8)؛ اول می‌پرسد
pattx dns udp 8.8.8.8 -y   # بدون سؤال (برای اسکریپت)
pattx dns restore          # برگرداندن
```

`pattx dns udp` هشدار می‌دهد، `y/N` می‌پرسد (بدون ترمینال فقط هشدار چاپ می‌کند و چیزی عوض نمی‌کند؛ `-y` سؤال را رد می‌کند)،
مقدارهای قبلی را در `/opt/pattx/dns.prev` ذخیره می‌کند، تغییر می‌دهد، PassWall2 را ری‌استارت می‌کند، چک می‌کند `github.com` resolve شود
و اگر نشد **خودش برمی‌گرداند**. `pattx passwall on` هم اگر Remote DNS برابر `tcp` باشد یادداشت چاپ می‌کند و پیشنهاد می‌دهد.
تنظیمات شما هیچ‌وقت بی‌صدا عوض نمی‌شود.

گزینه‌ها (روی نود XHTTP پشت Cloudflare تست شده: UDP/53 کار می‌کند، TCP/53 نه، HTTPS بله):

- **UDP** (`pattx dns udp`): ساده‌ترین، DNS ساده داخل تونل. نود باید UDP/53 را اجازه بدهد (pattx چک می‌کند).
- **DoH** (LuCI > PassWall2 > DNS، مثلاً `https://dns.google/dns-query,8.8.8.8`): رمزنگاری‌شده و روی تقریباً هر نودی کار می‌کند. اگر UDP جواب نداد از این استفاده کنید.
- detour برابر `direct` برای Remote DNS: همه‌جا کار می‌کند ولی کوئری‌های DNS بدون پروکسی از روتر خارج می‌شوند.

اگر بدون DNS گیر کردید: `/etc/init.d/passwall2 stop`، بعد `pattx update`، بعد دوباره PassWall2 را روشن کنید.

## محدودیت‌ها

- فقط هسته Xray. نسخه‌های `sing-box` و `mihomo` او استفاده نمی‌شوند (نیاز به glibc / CPU نسل v3).
- فقط x86_64 با OpenWrt 25.12 تست شده. معماری‌های دیگر در اسکریپت نگاشت شده‌اند ولی تست نشده‌اند.
- روتر برای آپدیت باید به github.com دسترسی داشته باشد.

## مجوز و اعتبار

اسکریپت‌های این ریپو: MIT. هسته Xray از patterniha و [XTLS/Xray-core](https://github.com/XTLS/Xray-core) (مجوز MPL-2.0) است
و از ریلیزهای خودشان دانلود می‌شود و در این ریپو بازتوزیع نمی‌شود.

</div>
