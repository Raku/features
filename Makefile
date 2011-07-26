features.html: process.pl template.html
	perl process.pl > features.html

clean:
	rm features.html
