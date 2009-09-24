#include <ruby.h>

#include <sys/ioctl.h>
#include <termios.h>
#include <util.h>
#include <errno.h>
#include <stdlib.h>



int lala(void) {


    struct termios ti;
    if (tcgetattr(0, &ti) < 0) {
	printf("tcgetattr failed %d\n", errno);
	return -1;
    }

    struct winsize ws;
    if (ioctl(0, TIOCGWINSZ, &ws) < 0) {
	printf("ioctl TIOCGWINSZ failed %d\n", errno);
	return -1;
    }

    printf("winsize: %d*%d %d*%d\n",
	   ws.ws_row, ws.ws_col, ws.ws_xpixel, ws.ws_ypixel);

    int master;
    int ret = forkpty(&master, NULL, &ti, &ws);
    if (ret < 0) {
	printf("forkpty failed %d\n", errno);
	return -1;
    }

    if (!ret) {
	// in child

/* 	if (tcsetattr(0, TCSANOW, &ti) < 0) { */
/* 	    printf("tcsetattr failed %d\n", errno); */
/* 	    exit(0); */
/* 	} */
/* 	if (ioctl(0, TIOCSWINSZ, &ws) < 0) { */
/* 	    printf("ioctl TIOCSWINSZ failed %d\n", errno); */
/* 	    exit(0); */
/* 	} */

	return 0;
    }

    return master;
}

static VALUE t_forkpty(VALUE self) {
//    printf("lala: %d\n", lala());
    return INT2FIX(lala());
}

static VALUE t_set_canon(VALUE self, VALUE vfd, VALUE vv) {
    int fd = FIX2INT(vfd);
    int v = FIX2INT(vv);

    struct termios ti;
    if (tcgetattr(fd, &ti) < 0) {
	printf("tcgetattr failed %d\n", errno);
	return self;
    }

    if (v) {
	ti.c_lflag |= ICANON;
    }
    else {
	ti.c_lflag &= ~ICANON;
	ti.c_cc[VMIN] = 0;
	ti.c_cc[VTIME] = 0;
    }

    if (tcsetattr(fd, TCSANOW, &ti) < 0) {
	printf("tcsetattr failed %d\n", errno);
	return self;
    }

    return self;
}

static VALUE t_set_echo(VALUE self, VALUE vfd, VALUE vv) {
    int fd = FIX2INT(vfd);
    int v = FIX2INT(vv);

    struct termios ti;
    if (tcgetattr(fd, &ti) < 0) {
	printf("tcgetattr failed %d\n", errno);
	return self;
    }

    if (v) {
	ti.c_lflag |= ECHO | ECHOE | ECHOKE | ECHONL;
    }
    else {
	ti.c_lflag &= ~(ECHO | ECHOE | ECHOKE | ECHONL);
    }

    if (tcsetattr(fd, TCSANOW, &ti) < 0) {
	printf("tcsetattr failed %d\n", errno);
	return self;
    }

    return self;
}

static VALUE t_set_winsize(VALUE self, VALUE fd, VALUE x, VALUE y) {
    struct winsize ws;
    memset(&ws, 0, sizeof(ws));
    ws.ws_col = FIX2INT(x);
    ws.ws_row = FIX2INT(y);

    if (ioctl(FIX2INT(fd), TIOCSWINSZ, &ws) < 0) {
	printf("ioctl TIOCSWINSZ failed %d\n", errno);
	return -1;
    }
    return self;
}

static VALUE t_get_winsize(VALUE self, VALUE fd) {
    struct winsize ws;
    memset(&ws, 0, sizeof(ws));

    if (ioctl(FIX2INT(fd), TIOCGWINSZ, &ws) < 0) {
	printf("ioctl TIOCSWINSZ failed %d\n", errno);
	return -1;
    }

    return rb_ary_new3(2, INT2FIX(ws.ws_col), INT2FIX(ws.ws_row));
}

/*
int main(int argc, char **argv) {
    lala();
    return 0;
}

static int id_push;
static VALUE t_init(VALUE self) {
    VALUE arr;
    arr = rb_ary_new();
    rb_iv_set(self, "@arr", arr);
    return self;
}

static VALUE t_add(VALUE self, VALUE obj) {
    VALUE arr;
    arr = rb_iv_get(self, "@arr");
    rb_funcall(arr, id_push, 1, obj);
    return arr;
}
*/

//VALUE cTest;
VALUE mod;
void Init_tty() {
//    cTest = rb_define_class("MyTest", rb_cObject);
//    rb_define_method(cTest, "initialize", t_init, 0);
//    rb_define_method(cTest, "add", t_add, 1);
//    id_push = rb_intern("push");

    mod = rb_define_module("TTY");
    rb_define_singleton_method(mod, "forkpty", t_forkpty, 0);
    rb_define_singleton_method(mod, "set_canon", t_set_canon, 2);
    rb_define_singleton_method(mod, "set_echo", t_set_echo, 2);
    rb_define_singleton_method(mod, "set_winsize", t_set_winsize, 3);
    rb_define_singleton_method(mod, "get_winsize", t_get_winsize, 1);

}

