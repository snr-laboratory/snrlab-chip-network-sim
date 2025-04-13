from cmath import log10
from pyclbr import readmodule
from tkinter.messagebox import NO
import serial
import _thread
import math
import sys
import time
import pyvisa
import matplotlib.pyplot as plt
from matplotlib.gridspec import GridSpec
from matplotlib.pyplot import MultipleLocator, xlabel
import mpl_toolkits.mplot3d
import numpy as np
# import xlwt
# import xlrd
from datetime import datetime
import os
from scipy.fft import rfft, rfftfreq
from scipy import signal
from matplotlib.pylab import mpl
from scipy import optimize
# import mplot




# def mFFT():
class FFTarray(object):

    def __init__(self):
        self.clear()

    def clear(self):
        self.x=None
        self.y=None
        self.fft=None
        self.energyArray=None
        self.magnitude_dB=None
        self.xDeltaTime=None
        self.averageFactor=1
        
        
        
    # def assignY(self, deltaTime, yArray):
    #     self.y=yArray
    #     self.fft = rfft(yArray)
    #     self.energyArray  = (np.abs(self.fft)*2/len(self.y))**2        
    #     self.xDeltaTime = deltaTime
    #     self.x= rfftfreq(len(self.y), deltaTime)
    #     self.updateMagnitude_dB()

    def assignY(self, deltaTime, yArray):
        self.y=yArray
        winLen= 2048
        self.x, self.fft = signal.welch(yArray, 1.0/deltaTime, nperseg=winLen)
        self.energyArray  = (np.abs(self.fft)*2/winLen)**2        
        self.xDeltaTime = deltaTime
        self.updateMagnitude_dB()

    

    def energy2Magnitude_dB(self, energy):        
        return 10*(np.log10(energy))

    def updateMagnitude_dB(self):
        self.magnitude_dB = self.energy2Magnitude_dB(self.energyArray)

    def getMagnitude_dB(self):
        self.updateMagnitude_dB()
        return self.magnitude_dB


    

    # magnitudeArray 为新的待平均的输入幅度谱
    # 根据self.averageFactor 权重因子  来计算新的平均数
    def averageAppend_dB(self, yarray, aveFactor=None):
        if( aveFactor is not None):
            self.averageFactor = aveFactor
        temp=FFTarray()
        temp.assignY(self.xDeltaTime, yarray)
        self.energyArray = (self.energyArray * self.averageFactor + temp.energyArray)/(self.averageFactor+1)
        self.averageFactor +=1        
        

    def loadXilinxILAs(self, deltaTime, fNameList, useCols=3, skipRows=2):
        print("FFTarray::loadXilinxILAs(): file list= ", fNameList)        
        for i in range(len(fNameList)):
            fName=fNameList[i]
            dataArray=np.loadtxt(fName,delimiter=',',skiprows=skipRows, usecols = useCols)
            if 0==i:
                self.assignY(deltaTime, dataArray)
            else:
                self.averageAppend_dB(dataArray)
        


    def selfPlot(self, xarray, yarray, blocked=False, **kwargs):
        figureIndex= kwargs.get('figureIndex')
        if(figureIndex is not None):
            plt.figure(figureIndex)
        xscale= kwargs.get('xscale')
        if(xscale is not None) :
            plt.xscale(xscale)
        else:
            plt.xscale('log')
        plt.step(xarray, yarray, alpha=0.5)
        plt.ylabel('dB')
        plt.xlabel('f [Hz]')
        if(blocked):
            plt.show()
            plt.pause(0.1)
    
    def plot(self, blocked=False, **kwargs):
        self.selfPlot(self.x, self.getMagnitude_dB(), blocked, **kwargs)
    
    def show(self):
        plt.show()
        plt.pause(0.1)

#   注意，基线用区间[xStop, xStop+ (xStop-xStart)] 的平均值代替


    def getPeak(self, start_Hz, stop_Hz):
        startIdx= np.argmax(self.x > start_Hz)        
        stopIdx = np.argmax(self.x > stop_Hz)
        meanEnergy = np.mean(self.energyArray[stopIdx:stopIdx*2-startIdx])
        temp=FFTpeak(self)
        temp.x            = self.x           [startIdx: stopIdx]
        temp.energyArray  = self.energyArray [startIdx: stopIdx]
        temp.magnitude_dB = self.magnitude_dB[startIdx: stopIdx]

        temp.energyBaselineSeg = np.full(stopIdx-startIdx, meanEnergy)
        temp.peakStartIndex=startIdx
        temp.peakStopIndex =stopIdx
        temp.updateENOB()
        
        return temp
        



# 测试用，赋初值 并显示
    def test(self, show=True):
        fSample=2**16
        deltaTime=1/fSample
        fSignal=1000
        t=np.arange(0,1,deltaTime)
        # 20dB for 1kHz;  0dB for 3kHz
        yarray=10*np.sin(2*np.pi*fSignal*t) + np.sin(2*np.pi*fSignal*3 *t)
        self.assignY(deltaTime, yarray)
        self.plot()
        if(show):
            self.show()



def XYseg_e_func(x, a0, a1, a2):
    return a0* np.exp(-x/a1) +a2

class XYseg(object):
    def __init__(self):
        self.clear()

    def clear(self):
        self.x=None
        self.y=None
        self.yFit = None
        self.parentX = None
        self.parentY = None
        self.startIndex=0
        self.stopIndex =0

    def getSeg(self, xarray, yarray, xstart, xstop):
        self.parentX = xarray
        self.parentY = yarray
        self.startIndex = np.argmax(xarray > xstart)        
        self.stopIndex  = np.argmax(xarray > xstop)
        self.x = xarray[self.startIndex: self.stopIndex]
        self.y = yarray[self.startIndex: self.stopIndex]

    def eFit(self):
        popt, pcov = optimize.curve_fit(XYseg_e_func, self.x, self.y)
        y2 = [XYseg_e_func(i, popt[0], popt[1], popt[2]) for  i in self.x]
        # print("y2", y2)
        self.yFit = np.array(y2)
        print("XYseg::eFit result: y=", popt[0], "*Exp(-x/", popt[1], ") + ", popt[2])
        print("                    y[x0]=", XYseg_e_func(self.x[0], popt[0], popt[1], popt[2]))
        print("                    RC constant=", popt[1])

    



def filt_cic(x, y, combDelay, Stage, decimation=1):
    '''
    Parameters:
    signal (numpy.array): input signal
    R (int): decimation rate
    M (int): number of differentiators
    N (int): number of integrators
    '''
    R = 1
    M = combDelay
    S = Stage
    # Integrator
    integ= y.copy()        
    for s in range(S):
        print("CIC integ...=", s)
        integ  = np.cumsum(integ)
    # Differentiator
    combArray= integ
    for s in range(S):
        print("CIC comb...=", s)
        for i in range(len(combArray)-1, -1, -1):
            if(i-M<0):
                temp=0
            else:
                temp=combArray[i-M]
            combArray[i] = (combArray[i] - temp)/M
    # Decimator
    return combArray[::R]


class MWave(object):
    def __init__(self):
        self.clear()

    def clear(self):
        self.txtList=list()
        self.xList=list()
        self.yList=list()
        self.x=None
        self.y=None
        self.axs =None

    def channel(self, ch, includeTxt= False):
        if(includeTxt):
            return (self.xList[ch], self.yList[ch], self.txtList[ch])
        else:
            return (self.xList[ch], self.yList[ch])
   
    def chCnt(self):
        return len(self.yList)

    def switchCh(self, chA, chB):
        temp=self.xList[chA]
        self.xList[chA] = self.xList[chB]
        self.xList[chB] = temp

        temp=self.yList[chA]
        self.yList[chA] = self.yList[chB]
        self.yList[chB] = temp

        temp=self.txtList[chA]
        self.txtList[chA] = self.txtList[chB]
        self.txtList[chB] = temp

    def __mapDefaultXY(self):
        self.x = self.xList[0]
        self.y = self.yList[0]

    def __update_xList(self):
        for i in range(len(self.xList), len(self.yList)):
            self.xList.append(self.xList[0].copy())


    


    def append(self, xArray, yArray, label=''):
        self.xList.append(xArray.copy()) 
        self.yList.append(yArray.copy())
        self.txtList.append(label)
        self.__mapDefaultXY()
        return self.chCnt()-1

    def assign(self, ch, xArray, yArray, label=''):
        self.xList[ch] = xArray
        self.yList[ch] = yArray
        self.txtList[ch] = label



    def load_csv_RIGOL(self, fName, deltaTime):
        # get line count
        with open(fName, 'r') as f: 
            first_line  = f.readline() 
            second_line = f.readline() 
            print(first_line)
        f.close()
        chCount = first_line.count(',')-3
        sParam = second_line.split(',')
        xStart=float(sParam[chCount+1])
        xDelta=deltaTime
        # get data
        self.xList.append( ( np.loadtxt(fName,delimiter=',',skiprows=2, usecols = 0) * deltaTime)  + xStart  )
        
        col = 1
        while( col< chCount+1 ):
            temp = np.loadtxt(fName,delimiter=',',skiprows=2, usecols = col)
            self.yList.append(  temp )
            self.txtList.append("Ch{}".format(col-1))
            col+=1            
        print("MWave::load_csv_RIGOL(", fName,")= Load", chCount, "channels successfully, with xStart=",xStart,", xDelta=", xDelta)
        print(self.yList)

        self.__mapDefaultXY()
        self.__update_xList()

    def load_csv_simple(self, fName, totalCols, fDelimiter=' ', skipRows= 1):
        # get line count
        with open(fName, 'r') as f: 
            first_line  = f.readline() 
            print(first_line)
        f.close()
        first_line.replace("#", '')
        lableList = first_line.split(';')
        self.xList.append( np.loadtxt(fName,delimiter=fDelimiter,skiprows=skipRows, usecols = 0)  )
        chCount = totalCols -1
        col=1
        while( col< totalCols ):
            temp = np.loadtxt(fName,delimiter=fDelimiter,skiprows=skipRows, usecols = col) 
            self.yList.append(  temp )
            self.txtList.append(lableList[col])
            col+=1
        self.__mapDefaultXY()
        self.__update_xList()
        print("MWave::load_csv_simple(", fName,")= Load", chCount, "channels successfully")
        print(self.yList)

    def load_txt_LTSpice(self, fName, signalCnt):
        # get line count
        lineCnt=0
        with open(fName, 'r') as fp:
            k=fp.readlines()
            lineCnt = len(k)
            colCnt= k[0].count('\t')
            self.txtList= k[0].replace('\n','').split('\t')[1:]
            print("load_txt_LTSpice() from", fName,"colCnt=", colCnt+1, "lineCnt=", lineCnt, "header info=", self.txtList)
            
        for i in range(colCnt+1):
            temp = np.loadtxt(fName,delimiter='\t',skiprows=1, usecols = i, max_rows=lineCnt-2)
            if(i<1):
                self.xList.append(temp)
            else:
                self.yList.append(  temp )
                self.xList.append(self.xList[0].copy())
        print(self.yList)

    def copyOneCh(self, ch):
        return ( self.xList[ch].copy(),   self.yList[ch].copy() , self.txtList[ch])

    def copyOneChSeg(self, ch, xstart=None, xstop=None, **kwargs):
        newWaveFlag=kwargs.get('newWave')   

        newWave = MWave()
        if(xstart is None or xstop is None):
            startIndex = 0   
            stopIndex  = -1
        else:  
            if(xstart < self.xList[ch][0]):
                startIndex = 0
            else:
                startIndex = np.argmax(self.xList[ch] > xstart)      

            if(xstop > self.xList[ch][-1]):
                stopIndex  = -1
            else:
                stopIndex  = np.argmax(self.xList[ch] > xstop)
        newWave.xList.append(self.xList[ch][startIndex: stopIndex])
        newWave.yList.append(self.yList[ch][startIndex: stopIndex])
        newWave.txtList.append(self.txtList[ch])
        if(newWaveFlag is not None):
            return newWave
        else:
            return ( newWave.xList[0].copy(),   newWave.yList[0].copy() , newWave.txtList[0])

    
    def replaceTxt(self, oldTxt, newTxt):
        for i in range(len(self.txtList)):
            self.txtList[i]= self.txtList[i].replace(oldTxt, newTxt)
        

    def decimate(self, rate, **kwargs): 
        ch=kwargs.get('ch')        
        if(ch is None):
            ch=0 
        segCnt = len(self.yList[ch])//rate
        points = len(self.xList[ch])//segCnt
        yn = np.zeros(segCnt)
        xn = np.zeros(segCnt)
        i=0
        while(i < segCnt):
            xn[i]= np.mean(self.xList[ch][points*i: points*(i+1)])
            yn[i]= np.mean(self.yList[ch][points*i: points*(i+1)])
            i+=1
        return (xn, yn)

    def minLevel(self, ch):
        return np.min(self.yList[ch])

    def maxLevel(self, ch):
        return np.max(self.yList[ch])


    def amplitude(self,ch):
        minY= np.min(self.yList[ch])
        amp = np.max(self.yList[ch])
        return amp - minY

    def level(self, ch, ampPercent):
        minL= self.minLevel(ch)
        maxL= self.maxLevel(ch)
        amp= maxL - minL
        lvl= ampPercent * amp + minL
        return lvl

    def midLevel(self, ch):
        return self.level(ch, 0.5)

    def idealize(self, deltaX, threshold=0.3, **kwargs):      
        ch=kwargs.get('ch')        
        if(ch is None):
            ch=0
        minY= np.min(self.yList[ch])
        absY= self.yList[ch] - minY
        amp = np.max(absY)
        print(self.xList)
        cnt=int((self.xList[ch][-1]-self.xList[ch][0])/deltaX)
        points = len(self.xList[ch])//cnt
        yn = np.zeros(cnt)
        xn = np.zeros(cnt)
        i=0
        while(i < cnt):
            ave= np.mean(absY[points*i: points*(i+1)])
            if(ave> threshold*amp):
                yn[i]=1
            else:
                yn[i]=0
            xn[i]=((i+1)*deltaX+ self.xList[ch][0])
            i+=1
        self.xList[ch] = xn.copy()
        self.yList[ch] = yn.copy()
        self.txtList[ch]+=" idealized"

    def idealize_LTSpice(self, deltaX, threshold=0.3, **kwargs):      
        ch=kwargs.get('ch')        
        if(ch is None):
            ch=0
        minY= np.min(self.yList[ch])
        absY= self.yList[ch] - minY
        amp = np.max(absY)
        print(self.xList)
        cnt=int((self.xList[ch][-1]-self.xList[ch][0])/deltaX)
        yn = np.zeros(cnt)
        xn = np.zeros(cnt)  
        xLast =self.xList[ch][0]
        idxNow=0      
        for i in range(cnt):
            xBegin= deltaX *i
            xEnd  = deltaX *(i+1)
            ySum  =0
            # sum for y in current seg
            while((idxNow<len(self.xList[ch])) and (self.xList[ch][idxNow]<xEnd)):
                ySum += (self.xList[ch][idxNow]-xLast) * absY[idxNow]
                xLast = self.xList[ch][idxNow]
                idxNow += 1
            yAve= ySum/deltaX
            if(yAve> threshold*amp):
                yn[i]=1
            else:
                yn[i]=0
            xn[i]=((i+1)*deltaX+ self.xList[ch][0])
            i+=1        
        self.xList[ch] = xn.copy()
        self.yList[ch] = yn.copy()
        self.txtList[ch]+=" idealized"

    def idealDiff(self, factor=1.0, **kwargs):      
        ch=kwargs.get('ch')        
        if(ch is None):
            ch=0
        temp=self.xList[ch].copy()
        temp.fill(0)
        pre=0
        for i in range(len(self.xList[ch])):
            if( self.yList[ch][i]>0):
                for k in range(pre,i+1):
                    temp[k]=factor*1.0/(self.xList[ch][i]-self.xList[ch][pre])
                pre=i
        return (self.xList[ch], temp)


    def plot_multiPanels(self, **kwargs):
        xLabel = kwargs.get('xlabel')
        if(xLabel is not None):kwargs.pop('xlabel')
        gs = GridSpec(len(self.yList), 1)
        self.axs=list()
        fig = plt.figure()
        # Remove horizontal space between axes
        # fig.subplots_adjust(hspace=0)

        for i in range(len(self.yList)):
            self.axs.append(plt.subplot(gs[i,0])) 
            self.axs[i].plot(self.xList[i], self.yList[i], label= self.txtList[i])
            self.axs[i ].legend(loc="upper right")
            self.axs[i ].set(ylabel="[V]")
        if(xLabel is None):
            self.axs[i ].set(xlabel="Time")
        else:
            self.axs[i ].set(xlabel=xLabel)


    def step(self, scatter = False, **kwargs):
        ch=kwargs.get('ch')        
        if(ch is None):# default plot
            for i in range(self.chCnt()):
                plt.step(self.xList[i], self.yList[i])
                if(scatter):
                    plt.scatter(self.xList[i], self.yList[i])
        else:
            plt.step(self.xList[ch], self.yList[ch])
            if(scatter):
                plt.scatter(self.xList[ch], self.yList[ch])

    def substep(self, **kwargs):
        xLabel = kwargs.get('xlabel')
        if(xLabel is not None):kwargs.pop('xlabel')
        fig, self.axs = plt.subplots(self.chCnt() ,1)       
        # fig.suptitle('Vertically stacked subplots')
        for i in range(self.chCnt()):
            self.axs[i ].step(self.xList[i], self.yList[i], label= self.txtList[i], **kwargs)
            self.axs[i ].legend(loc="upper right")
            self.axs[i ].set(ylabel="[V]")
        
        if(xLabel is None):
            self.axs[i ].set(xlabel="Time [s]")
        else:
            self.axs[i ].set(xlabel=xLabel)

    def setPlotYLabel(self, ch, txt):
        self.axs[ch].set(ylabel= txt)

        

    def filt_CIC(self, combDelay, Stage, **kwargs):      
        ch=kwargs.get('ch')        
        if(ch is None):
            ch=0
        mcic = filt_cic(self.xList[ch], self.yList[ch],combDelay, Stage)        
        # plt.step(self.x, mcic)
        return (self.xList[ch],  mcic)

    def filt_movingAve(self, winSize, stage = 1, **kwargs):
        channel=kwargs.get('ch')        
        if(channel is None):
            channel=0
        fA=self.yList[channel].copy()
        for s in range(stage):
            temp= fA.copy()
            for i in range(len(self.yList[channel])):
                startIdx= i-winSize+1
                if(startIdx<0): startIdx = 0
                fA[i] = np.sum(temp[startIdx:i])/winSize
        # plt.step(self.x, fA )
        return (self.xList[channel],  fA)

    def filt_FIR(self, **kwargs):      
        ch=kwargs.get('ch')        
        if(ch is None):
            ch=0

        fc=kwargs.get('fc')        
        if(fc is None):
            fc = 100000  # 截止频率

        fs=kwargs.get('fs')        
        if(fs is None):
            fs = 1666666  # 采样频率

        N=kwargs.get('N')        
        if(N is None):
            N = 51  # 滤波器阶数

        # 设计FIR低通滤波器
        
        
        
        b = signal.firwin(N, fc, fs=fs)  # FIR滤波器系数

        # 计算FIR滤波器的幅频响应
        w, h = signal.freqz(b)

        # 绘制幅频响应图
        # plt.plot(w/np.pi*fs/2, 20*np.log10(np.abs(h)))
        # plt.xlabel('Frequency (Hz)')
        # plt.ylabel('Magnitude (dB)')
        # plt.title('FIR Lowpass Filter Frequency Response')
        # plt.grid()

        return (self.xList[ch], signal.filtfilt(b,1.0, self.yList[ch]) )

         
    def cnt_posedge(self, ch, threshold=0.5):
        cnt=0
        xlen= len(self.yList[ch])
        th= self.level(ch, threshold)
        for i in range(xlen-1):
            if( (self.yList[ch][i] < th) and (self.yList[ch][i+1] >= th) ):
                cnt += 1
        return cnt

    def cnt_negedge(self, ch, threshold=0.5):
        cnt=0
        xlen= len(self.yList[ch])
        th= self.level(ch, threshold)
        for i in range(xlen-1):
            if( (self.yList[ch][i] > th) and (self.yList[ch][i+1] <= th) ):
                cnt += 1
        return cnt




        



		


class integrator:
	def __init__(self):
		self.yn  = 0
		self.ynm = 0
	
	def update(self, inp):
		self.ynm = self.yn
		self.yn  = (self.ynm + inp)
		return (self.yn)
		
class comb:
	def __init__(self):
		self.xn  = 0
		self.xnm = 0
	
	def update(self, inp):
		self.xnm = self.xn
		self.xn  = inp
		return (self.xn - self.xnm)

class CIC(object):
    def __init__(self, sampleCnt, decimationCnt, stageCnt):
        self.samples            = sampleCnt +1 # extra one to ensure the combs run on the final iteration.
        self.decimation         = decimationCnt # any integer; powers of 2 work best.
        self.stages             = stageCnt # pipelined I and C stages
        ## Calculate normalising gain
        self.gain = (self.decimation * 1) ** self.stages
        ## Seperate Stages - these should be the same unless you specifically want otherwise.
        

    def filter(self, x, y):
        c_stages = self.stages
        i_stages = self.stages
        ## Generate Integrator and Comb lists (Python list of objects)
        intes = [integrator() for a in range(i_stages)]
        combs = [comb()	      for a in range(c_stages)]

        

        # input_samples    = [inp_samp(a/samples) for a in range(samples)]
        output_samples   = []
        for p in range(len(x)):
            z = y[p]
            for i in range(i_stages):
                z = intes[i].update(z)

            if (p % self.decimation) == 0: # decimate is done here
                for c in range(c_stages):
                    z = combs[c].update(z)
                    j = z
                output_samples.append(j/self.gain) # normalise the gain

        wave= MWave()
        wave.x=np.arange(x[0], x[-1], self.decimation*(x[1]-x[0]))
        wave.yList.append(np.array(output_samples))
    
        return wave
        

def Main1():
    os.chdir(os.path.dirname(__file__))
    print (os.path.abspath('.'))

    wave=MWave()
    wave.load_csv_simple("230111_0PF1_10x100MOhm_L57H57_ChargeInj_5.csv", 4)
    # print(wave.x)
    plt.plot(wave.x, wave.yList[0]*-0.1+0.5)
    plt.plot(wave.x, wave.yList[1])
    # plt.plot(wave.x, wave.yList[2])
    # plt.plot(wave.x)
    # plt.plot(wave.y[1])

    # seg = XYseg()
    # seg.getSeg(wave.x, wave.y[1], 0.01, 0.018)
    # seg.eFit()

    # plt.plot(seg.x, seg.yFit)

    # seg2= XYseg()
    # seg2.getSeg(wave.x, wave.yList[1], 0.009, 0.0098)
    # err=np.std(seg2.y)
    # print("Noise", err)
    # print("Noise w/o QN =", (err**2-((0.00156**2)/12))**(0.5))

    # plt.grid()
    gap=0.6
    x0=wave.x[0]
    cnt=(wave.x[-1]-wave.x[0])/gap
    print("total seg count=", cnt,"seg points=",len(wave.x)/cnt)
    i=0
    # while(i < cnt):
    #     plt.axvline(x = x0+ gap*i ,color = 'gray')
    #     i+=1

    # multiD=5
    
    for i in range(10):
        decim=6000 * (1+i)
        cic = CIC(len(wave.x), decim, 1)
        newWave=cic.filter(wave.x, wave.yList[1]+0.736)
        plt.plot(newWave.x, newWave.yList[0], label="decimation={}".format(decim))
    plt.legend(loc='upper right')


    plt.figure(5)
        
    fs=1000000/(wave.x[1]-wave.x[0])
    print("Frequency=",fs)
    fc = 300000  # Cut-off frequency of the filter
    w = fc / (fs / 2) # Normalize the frequency
    b, a = signal.butter(3, w, 'low')
    output = signal.filtfilt(b, a, wave.yList[1]+0.736)
    plt.plot(wave.x, output, label='filtered')
    plt.legend()


    plt.show()
    plt.pause(0.1)


def cic_filter(signal, R, M, N):
    """
    CIC filter implementation in Python
    
    Parameters:
    signal (numpy.array): input signal
    R (int): decimation rate
    M (int): number of differentiators
    N (int): number of integrators
    
    Returns:
    numpy.array: filtered signal
    """
    # Differentiator
    for i in range(M):
        signal = np.diff(signal)
        
    # Integrator
    for i in range(N):
        signal = np.cumsum(signal)
        
    # Decimator
    return signal[::R]






def Main2():
    os.chdir(os.path.dirname(__file__))
    print (os.path.abspath('.'))

    wave=MWave()
    wave.load_csv_simple("230111_0PF1_10x100MOhm_L57H57_ChargeInj_5.csv", 4)
    # print(wave.x)
    
    # plt.plot(wave.x, wave.yList[2])
    # plt.plot(wave.x)
    # plt.plot(wave.y[1])

    # seg = XYseg()
    # seg.getSeg(wave.x, wave.y[1], 0.01, 0.018)
    # seg.eFit()

    # plt.plot(seg.x, seg.yFit)

    # seg2= XYseg()
    # seg2.getSeg(wave.x, wave.yList[1], 0.009, 0.0098)
    # err=np.std(seg2.y)
    # print("Noise", err)
    # print("Noise w/o QN =", (err**2-((0.00156**2)/12))**(0.5))

    wave.switchCh(1,2)
    wave.append(*wave.copyOneCh(2))
    rstWave= wave
    rstWave.yList[0] = rstWave.yList[0]* -1 +0.3
    rstWave.idealize(0.6, 0.3, ch=3)

    

    # wave.x /= 1000000
    # rstWave.x /= 1000000
    # rstWave.yList[0].fill(0)
    # rstWave.yList[0][0]=1
    # rstWave.yList[0] = rstWave.yList[0] 
    
    # fig = plt.figure(2)
    # ax = fig.add_subplot(projection='3d')  
    # for s in range(1,16):
    #         # for d in range(1, 10):
    #         d= 18-s
    #         ax.step(rstWave.x, rstWave.filt_movingAve(d, s), zs=s*100+d, zdir='y', alpha=0.8)
    #         ax.step(rstWave.x, rstWave.filt_CIC(d, s), zs=s*100+d+4000, zdir='y', alpha=0.8)

    d=3
    s=3
    plt.figure(2)
    rstWave.step()
    rstWave.append(*rstWave.filt_CIC(d, s, ch=3), "CIC filtered")
    rstWave.append(*rstWave.idealDiff(0.46, ch=3), "Ideal diff")
    deciInCh = rstWave.append(*rstWave.decimate(1000, ch=0))
    rstWave.append(*rstWave.filt_FIR(ch=deciInCh, fs=10000000, fc=200000, N=51), "Input signal FIR")
    rstWave.append(*rstWave.filt_FIR(ch=3, fs=1666666, fc=200000, N=51), "Reset signal FIR")
    rstWave.substep(xlabel='Time [us]')
    # plt.step(rstWave.xList[1], rstWave.idealDiff(1, ch=1))

    

    plt.figure(4)
    plt.plot(*rstWave.channel(0))
    plt.step(*rstWave.channel(3))
    plt.step(*rstWave.channel(5))

    plt.figure(5)
    plt.plot(*rstWave.channel(deciInCh))
    for i in range(20):
        plt.step(*rstWave.filt_FIR(ch=3, fs=1666666, fc=1000+10000*i, N=51))

    # mfftCIC = FFTarray()
    # mfftCIC.assignY(rstWave.x[1]-rstWave.x[0], rstWave.filt_movingAve(d, s))
    # aT= np.zeros(65536)
    # aT[65536//2]=1
    # mfftCIC.assignY(0.000001, aT)
    # mfftCIC.plot()
    

    

    # R=1
    # for r in range(1):
    #     R=1+r*2
    #     for n in range(1,5):
    #         plt.figure(n)
    #         plt.step(xn,yn-1.5)
    #         plt.plot(wave.x, wave.yList[0]*-0.3+1.5)
    #         for i in range(1,10):               
                
    #             decim=i+1
    #             cic = CIC(len(xn), decim, n)
    #             newWave=cic.filter(xn, yn)
    #             # newWave=MWave()
    #             # newWave.x=xn
    #             # newWave.yList.append(cic_filter(yn,R,decim,n))            
    #             # plt.plot(np.linspace(newWave.x[0],newWave.x[-1],len(newWave.yList[0])), newWave.yList[0], label="R={}, stage={}, decimation={}".format(R, n, decim))
    #             plt.step(newWave.x, newWave.yList[0], label="stage={}, decimation={}".format( n, decim))
    #         plt.legend(loc='upper right')
    # # multiD=5
    
    

    
    
    # for i in range(10):
    #     plt.figure(10+i)
    #     fs=1000000/(0.6)
    #     print("Frequency=",fs)
    #     plt.step(xn,yn-1.5)
    #     fc = 30000*(i+1)  # Cut-off frequency of the filter
    #     w = fc / (fs / 2) # Normalize the frequency
    #     b, a = signal.butter(3, w, 'low', analog=False)
    #     output = signal.filtfilt(b, a, yn)
    #     plt.plot(xn, output, label='filtered')
    #     plt.legend()
    # # for i in range(10):
    # #     cic = CIC(len(wave.x), 6000 * (1+i), 5)
    # #     newWave=cic.filter(wave.x, wave.yList[1]+0.736)
    # #     plt.plot(newWave.x, newWave.yList[0])
    plt.show()
    plt.pause(0.1)




class Pic(object):
    def __init__(self):
        self.clear()


    def clear(self):
        self.yList=None

    def load_csv(self, fName, colCnt, skipRow=0, delimiterCh=','):
        # get line count
        
        temp =(  )  
        
        self.yList = list()
        
        for i in range(colCnt):
            temp = np.loadtxt(fName,delimiter=delimiterCh,skiprows=skipRow, usecols = i)
            self.yList.append(  temp )
        print(self.yList)

class PlotCsv(object):
    def __init__(self):
        self.clear()



    def clear(self):
        self.yList=None
        self.axs=None

    def load_csv(self, fName, colCnt, skipRow=0, delimiterCh=',', maxRowCnt=None):
        # get line count
        
        temp =(  )  
        
        self.yList = list()
        
        for i in range(colCnt):
            temp = np.loadtxt(fName,delimiter=delimiterCh,skiprows=skipRow, usecols = i, max_rows=maxRowCnt)
            self.yList.append(  temp )
        print(self.yList)

    def plot(self):
        gs = GridSpec(len(self.yList), 1)
        self.axs=list()
        fig = plt.figure(1)
        # Remove horizontal space between axes
        # fig.subplots_adjust(hspace=0)

        for i in range(len(self.yList)):
            self.axs.append(plt.subplot(gs[i,0])) 
            self.axs[i].plot(self.yList[i])



        


def main_wave():
    os.chdir(os.path.dirname(__file__))
    print (os.path.abspath('.'))

    wave = MWave()
    wave.load_txt_LTSpice("LMP7721_Wave_1G_20230323_GoodResult.txt",4)
    wave.replaceTxt("I(V9)", "Input current")
    newWave= wave.copyOneChSeg(2, 0.00068, 0.0008, newWave = True)

    # plt.plot(wave.xList[2], wave.yList[2])
    wave.idealize_LTSpice(0.0000006, 0.3, ch=2)
    # plt.plot(wave.xList[2], wave.yList[2])
    # plt.plot(wave.xList[0], wave.yList[3]*1000000000)
    
    newWave.append(* wave.copyOneChSeg(2, 0.00068, 0.0008) )
    d=2
    s=10
    # plt.figure(2)
    
    newWave.append(*newWave.filt_CIC(d, s, ch=1), "CIC filtered, Delay={}, Stages={}".format(d,s))
    newWave.yList[-1] *= (0.33/0.6)
    d=8
    s=1
    newWave.append(*newWave.filt_CIC(d, s, ch=1), "CIC filtered, Delay={}, Stages={}".format(d,s))
    newWave.yList[-1] *= (0.33/0.6)
    newWave.append(*newWave.idealDiff(0.33 * 0.000001, ch=1), "RTD")
    # newWave.yList[-1] *= (0.33 * 0.000001)
    newWave.append(*newWave.filt_CIC(2, 3, ch=4), "RTD then CIC filterd")
    newWave.append(*wave.copyOneChSeg(3, 0.00068, 0.0008))
    newWave.yList[-1] *= 1000000000
    # newWave.step()
    
    # plt.plot(newWave.xList[0], newWave.yList[0])
    newWave.substep()

    plt.figure()

    for i in range(7):
        if(i>1):
            newWave.setPlotYLabel(i, "[nA]")
            plt.step(newWave.xList[i], newWave.yList[i], label=newWave.txtList[i])
    plt.xlabel("time [s]")
    plt.ylabel("Current [nA]")
    plt.legend()

    
    # for i in range(20):
    #     plt.figure()
    #     for k in range(10):
    #         plt.plot(*newWave.filt_CIC(1+i, 1+k, ch=1), label= "Stages={}".format(k+1))
    #         plt.title("CIC filtered, Delay={}".format(i+1))
    #         plt.legend(loc="upper right")
    # plt.plot(newWave.xList[1], newWave.yList[1])
    # plotcsv.plot()
    
    # plt.plot(wave.xList[0], wave.yList[1])
    # plt.plot(wave.xList[0], wave.yList[2])
    # plt.plot(wave.xList[0], wave.yList[3])
    # plt.rcParams.update({'font.size': 11})
    
    # pic= Pic()
    # pic.load_csv("LMP7721_Cin_1G_20230104 - 副本.txt", 5, 1)

    # gs = GridSpec(5, 1)
    # axs=[3,3,3,3,3]
    # print(axs)
    # fig = plt.figure(1)
    # # fig, axs = plt.subplots(2, 2, sharex=True, gridspec_kw={'height_ratios': [1, 1]})

    # # Remove horizontal space between axes
    # fig.subplots_adjust(hspace=0)

    # for i in range()
    # axs[0] = plt.subplot(gs[0,0])
    # axs[1] = plt.subplot(gs[1,0])
    # axs[2] = plt.subplot(gs[1,0])
    # axs[3] = plt.subplot(gs[1,0])
    # axs[1] = plt.subplot(gs[1,0])
    # # axs[2] = plt.subplot(gs[0:,1])
    

    # # print(wave.x)
    # axs[0].step(pic.yList[0], pic.yList[1], label="100% duty cycle for reset")
    # # axs[0].plot(pic.yList[1], pic.yList[0], label="Measured")
    # # axs[0].plot(pic.yList[0], pic.yList[2], color='red', linestyle='--', label="Linear fit")
    
    # # axs[0].legend(bbox_to_anchor=(0.1, 600), loc="lower left")
    
    # for i in range(9):
    #     axs[0].axvline(x=600*i, color='gray', linestyle='dotted')
    #     axs[1].axvline(x=600*i, color='gray', linestyle='dotted')
    # # axs[0].axvline(x=0, color='gray', linestyle='dotted')
    # # txtStr = "Linear fit result:\ny=460*x+2.88\n$\mathit{R}$$^2$=0.999961366346264"
    # # axs[0].text(1.2, 300, txtStr, verticalalignment='top')
    # # axs[0].legend(bbox_to_anchor=(0.3, 0.8), loc="lower left", fontsize=fsize)

    # str="  C$_f$ \nreset"
    # x_reset0 = 700
    # x_reset1 = 2500+600
    # fsize = 14
    # axs[0].text(x_reset0, 0.5, str, verticalalignment='top' , fontsize=fsize)
    # axs[0].text(x_reset1, 0.5, str, verticalalignment='top' , fontsize=fsize)
    # axs[0].text(x_reset1+600, 0.5, str, verticalalignment='top', fontsize=fsize)

    # axs[0].set( ylabel='NMOS Gate Control')

    # axs[1].step(pic.yList[0], pic.yList[2], label="50% duty cycle for reset")
    

    # # axs[1].scatter(pic.yList[0], pic.yList[1]-pic.yList[2])
    # axs[1].set(xlabel='time [ns]', ylabel='NMOS Gate Control')
    # # axs[1].axhline(y=0, color='gray', linestyle='dotted')
    # # axs[1].axvline(x=0, color='gray', linestyle='dotted')

    # x_major_locator = MultipleLocator(600)

    # x0=np.array([600,1200])
    # x1=np.array([3000,4200])
    # y1=1.5
    # y0=-0.5
    # for i in range(2):
    #     axs[i].fill_between(x0,y0,y1,facecolor='yellow',alpha=0.2)
    #     axs[i].fill_between(x1,y0,y1,facecolor='yellow',alpha=0.2)
    #     axs[i].set_ylim(-0.2, 1.4)
    #     axs[i].set_yticks([0,1])
    #     axs[i].set_yticklabels(['Off', 'On'])
    #     axs[i].legend(bbox_to_anchor=(0.3, 0.8), loc="lower left")
    #     axs[i].xaxis.set_major_locator(x_major_locator)

    # axs[0].axes.xaxis.set_visible(False)

    # # pic2= Pic()
    # # pic2.load_csv("data.csv", 3, 1)
    # # axs[2].plot(pic2.yList[0], pic2.yList[1])
    
    

    plt.show()
    plt.pause(0.1)





def main_deltaQ():
    os.chdir(os.path.dirname(__file__))
    print (os.path.abspath('.'))

    wave = MWave()
    wave.load_txt_LTSpice("LMP7721_Wave_1G_20230323_GoodResult_deltaQ.txt",1)
    # wave.step()

    # newWave= wave.copyOneChSeg(0, 0.00011628, 0.00012551, newWave = True)
    t0 = 0.000103
    t1 = 0.001
    newWave= wave.copyOneChSeg(0, t0, t1, newWave = True)
    xcnt = (t1-t0)/0.0000006
    xedge= newWave.cnt_posedge(0)
    rate = xedge/xcnt
    print("xcnt=",xcnt,"xedge=",xedge, "rate=", rate )
    # 0.5nA * 0.6us = 0.3fC   /rate
    print("delta Q=",0.5*0.6/rate )
    newWave.step()
    print(newWave.cnt_posedge(0))
    

    # # plt.plot(wave.xList[2], wave.yList[2])
    # wave.idealize_LTSpice(0.0000006, 0.3, ch=2)
    # # plt.plot(wave.xList[2], wave.yList[2])
    # # plt.plot(wave.xList[0], wave.yList[3]*1000000000)
    
    # newWave.append(* wave.copyOneChSeg(2, 0.00068, 0.0008) )
    # d=2
    # s=11
    # # plt.figure(2)
    
    # newWave.append(*newWave.filt_CIC(d, s, ch=1), "CIC filtered, Delay={}, Stages={}".format(d,s))
    # d=8
    # s=1
    # newWave.append(*newWave.filt_CIC(d, s, ch=1), "CIC filtered, Delay={}, Stages={}".format(d,s))
    # newWave.append(*newWave.idealDiff(ch=1), "RTD")
    # newWave.append(*newWave.filt_CIC(2, 3, ch=4), "RTD then CIC filterd")
    # newWave.append(*wave.copyOneChSeg(3, 0.00068, 0.0008))
    # # newWave.step()
    
    # # plt.plot(newWave.xList[0], newWave.yList[0])
    # newWave.substep()

    

    plt.show()
    plt.pause(0.1)






if __name__ == "__main__":
    # main_deltaQ()
    main_wave()