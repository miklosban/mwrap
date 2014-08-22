#

if(!exists('csv')) {
    csv <- 'P1060509.MOV.dir/gyerök.csv2'
}

ev<-read.csv2(csv,sep=';',header=F,col.names=c('id','text','code','time','length'),comment.char='#')
pdf("plots.pdf") 

#png('plots.png');

a <- ev[ev$length==0,]
b <- ev[ev$length!=0,]
a$time<-as.numeric(paste(a$time))
b$time<-as.numeric(paste(b$time))
b$length<-as.numeric(paste(b$length))

ev$time <- as.numeric(levels(ev$time))[ev$time]

bb <- b
bb$time<-b$time-b$length

x<-a$id[a$code==b$code&a$time==(b$time-b$length)]
a <- a[a$id!=x,]

for (i in b$id) {
    for(j in 1:floor(b$length[b$id==i])) {
        bb <- rbind(bb,b[b$id==i,])
    }
}

#bb<-rbind(b,bb)

events<-unique(a$text)
#a$time[a$text=='fordul']
#m <- 0
#for (i in 1:length(events)) {
#    if( length(a$time[a$text==as.character(events[i])])>m ) {
#        m <- length(a$time[a$text==as.character(events[i])])
#    }
#}

# diszkrét események előfordulási aránya

cols <- data.frame(unique(ev$code),rainbow(length(unique(ev$code))))
cl <- c()
leg.txt <- paste(unique(ev$text))

plot(seq(1,ceiling(max(ev$time))),seq(1,ceiling(max(ev$time))),type='n',frame.plot=T,axes=F,xlab='time',ylab='percent')
axis(1,ev$time)
x <- length(ev$time)
axis(2,seq(from=0,to=max(ev$time),length.out=11),labels=seq(from=0,to=100,by=10),tick=TRUE)
pchh <- c()

for (i in unique(a$code)) {
    #print(cols[,2][cols[,1]==i])
    lines(sort(a$time[a$code==i]),seq(1,length(a$time[a$code==i])),lty=3,col=cols[,2][cols[,1]==i])
    points(sort(a$time[a$code==i]),seq(1,length(a$time[a$code==i])),pch=16,col=cols[,2][cols[,1]==i])
    cl[[length(cl)+1]] <- as.character(cols[,2][cols[,1]==i])
    pchh[[length(pchh)+1]] <- 16
}

# folyamatos események előfordulási aránya
m <- 0
for (i in unique(bb$id)) {

    bb$time[bb$id==i] <- seq(min(bb$time[bb$id==i]),max(bb$time[bb$id==i]))
    j <- length(bb$time[bb$id==i])
    #print(cols[,2][cols[,1]==unique(bb$code[bb$id==i])])

    lines(sort(bb$time[bb$id==i]),seq(m+1,j+m),col=cols[,2][cols[,1]==unique(bb$code[bb$id==i])],lty=1)
    points(sort(bb$time[bb$id==i]),seq(m+1,j+m),pch=4,col=cols[,2][cols[,1]==unique(bb$code[bb$id==i])])
    m <- j-1
    cl[[length(cl)+1]] <- as.character(cols[,2][cols[,1]==unique(bb$code[bb$id==i])])
    pchh[[length(pchh)+1]] <- 4
}
legend(x=1,y=10, legend = leg.txt, col=cl,pch=pchh,lty=1, merge=TRUE)#, trace=TRUE)
title("events' ratio")


# diszkrét események gyakorisági görbéje
plot(c(0:max(a$time)),c(0:max(a$time)),frame.plot=T,axes=F,type='n',xlab='time',ylab='frequency')
leg.txt <- paste(unique(a$code),unique(a$text))
cl <- c()
mk <- 0
for (i in unique(a$code)) {
    k <- a$time[a$code==i]
    z <- c(0,k)
    z <- z[1:length(k)]
    k-z
    lines(seq(from=min(k),to=max(k),length.out=length(spline(k-z)$y)),spline(k-z)$y,type='l',col=cols[,2][cols[,1]==i])
    cl[[length(cl)+1]] <- as.character(cols[,2][cols[,1]==i])
    if (length(spline(k-z)$y)>mk) {
        mk <- length(spline(k-z)$y)
    }
}

axis(1,a$time)
legend(x=1,y=mk, legend = leg.txt, col=cl,lty=1, merge=TRUE)#, trace=TRUE)
title("Discrete events' frequency")

#for (i in unique(bb$time)) {
#    j <- unique(bb$code[bb$time==i])
#    lines(sort(bb$time[bb$time==i]),seq(1,length(bb$time[bb$time==i])),col=cols[,2][cols[,1]==j])
#}

#seq(1:ceiling(max(ev$time)))
#sort(ev$time)
#plot(sort(ev$time),rep(1,12))

dev.off()
