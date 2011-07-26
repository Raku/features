features.html: process.pl template.html features.json
	perl process.pl features.html
clean:
	rm features.html
