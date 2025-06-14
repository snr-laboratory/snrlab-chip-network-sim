from pyclbr import readmodule
from tkinter.messagebox import NO
import serial
import _thread
import math
import sys
import time
import pyvisa
import matplotlib.pyplot as plt
import mpl_toolkits.mplot3d
import numpy as np
# import xlwt
# import xlrd
from datetime import datetime
import os
from scipy.fft import rfft, rfftfreq
from scipy import signal



##############################################################################################################################
# Class DG1022   waveform generator
#
#
##############################################################################################################################
class DG1022(object):  

    def openDevice(self):
        visa = pyvisa.ResourceManager()
        print("\nDG1022 openning...")
        print("VISA list:",visa.list_resources())
        time.sleep(0.5)
        self.usb1022 = visa.open_resource('USB0::0x1AB1::0x0588::DG1D131402088::INSTR')
        time.sleep(0.5)
        self.usb1022.write("*IDN?")
        time.sleep(0.5)
        str=self.usb1022.read()
        print("Device IDN:",str,end=' ')
        if('RIGOL TECHNOLOGIES,DG1022 ,DG1D131402088,,00.02.00.06.00.02.07\n' != str):
            print("DG1022::openDevice()= Error: failed to query ID!")
            os.abort()
        else:
            print("Open DG1022 successfully")

    def setCh1_Sin_Hz_V_V(self, freq_Hz, amp_V, offset_V):
        str="APPL:SIN "+f'{freq_Hz}'+","+f'{amp_V}'+","+f'{offset_V}'
        print("DG1022 set ch1 sin:",str)
        self.usb1022.write(str)
        time.sleep(0.5)

    def setCh1_Frequency_Hz(self, freq_Hz):
        str="FREQ "+f'{freq_Hz}'
        print("DG1022 set ch1 frequency:",str)
        self.usb1022.write(str)
        time.sleep(0.5)

    def setCh1_On(self, on=True):
        if(on):
            self.usb1022.write("OUTP ON")
        else:
            self.usb1022.write("OUTP OFF")
        time.sleep(0.5)

    def closeDevice(self):
        self.usb1022.close()


    ## Generate tail-pulse and write into instrument's memory
    # @param xp number of samples before the edge
    # @param np total number of samples for the pulse
    # @param alpha exp-decay coefficient in exp(-alpha * (i - xp))
    def setVolatileMemData(self, freq, dataArray):
        self.usb1022.write("FUNC USER")
        time.sleep(0.5)
        self.usb1022.write("FREQ %g" % freq)
        time.sleep(0.5)
        string = "DATA:DAC VOLATILE"
        for i in dataArray:
            k= int(i)
            string += (",%d"% k)
        self.usb1022.write(string)
        print(string)
        time.sleep(1.0)
        self.usb1022.write("FUNC:USER VOLATILE")
        time.sleep(0.5)

    def set_voltage(self, vLow=0.0, vHigh=1.0):
        self.usb1022.write("VOLT:UNIT VPP")
        time.sleep(0.5)
        self.usb1022.write("VOLTage:LOW %g" % vLow)
        time.sleep(0.5)
        self.usb1022.write("VOLTage:HIGH %g" % vHigh)
        time.sleep(0.5)



##############################################################################################################################
# Class MSO9254A Oscilloscope
#
#
##############################################################################################################################



class MSO9254A(object): 
    def osAbort(self):
        self.closeDevice() 
        os.abort()

    def openDevice(self):
        visa = pyvisa.ResourceManager()
        print("\nMSO9254A oscilloscope openning...")
        print("VISA list:",visa.list_resources())
        time.sleep(0.5)
        self.usb9254 = visa.open_resource('USB0::0x2A8D::0x900E::MY51420128::INSTR')
        time.sleep(0.5)
        self.usb9254.write("*IDN?")
        time.sleep(0.5)
        str=self.usb9254.read()
        print("Device IDN:",str,end=' ')
        if('KEYSIGHT TECHNOLOGIES,MSO9254A,MY51420128,06.00.01201\n' != str):
            print("nMSO9254A::openDevice()= Error: failed to query ID!")
            self.abort()
        else:
            print("Open MSO9254A oscilloscope successfully")

    def closeDevice(self):
        self.usb9254.close()

    
    def resetMeasureStatistics(self):
        timeScale=float(self.usb9254.query(":TIMebase:SCALe?"))
        self.setTimeBase_s(timeScale*10, False)
        time.sleep(0.5)
        self.setTimeBase_s(timeScale, False)
        time.sleep(0.5)


    def fetchMeasureMean(self, index=0, minCounts=100, autoResetStatistics=True):
        self.usb9254.write(":MEASure:STATistics ON")
        self.usb9254.write(":MEASure:SENDvalid ON")
        if(autoResetStatistics):self.resetMeasureStatistics()
        cnt=0
        while(cnt<minCounts):
            time.sleep(0.5)
            str=self.usb9254.query(":MEASure:RESults?")
            strlist=str.split(',')
            cnt=float(strlist[7+8*index])
            measCnt=len(strlist)//8
            if(measCnt<=index):
                print("MSO9254A::fetchMeasureMean()=ERROR: index outof range! Measurement count=",measCnt)
                self.osAbort()
            valueMean=float(strlist[5+8*index])
            print("measurement mean:",valueMean,"counts=",cnt)
            time.sleep(1)

    def fetchMeasureMeanList(self, measureTypes, minCounts=100, autoResetStatistics=True):
        self.usb9254.write(":MEASure:STATistics ON")
        self.usb9254.write(":MEASure:SENDvalid ON")
        if(autoResetStatistics):self.resetMeasureStatistics()
        cnt=0
        valueMean= np.array([])
        while(cnt<minCounts):
            time.sleep(0.5)
            str=self.usb9254.query(":MEASure:RESults?")
            strlist=str.split(',')
            measCnt=len(strlist)//8
            cnt=float(strlist[7])
            
            if(measCnt<measureTypes):
                print("MSO9254A::fetchMeasureMeanList()=ERROR: Measurement count only =",measCnt, "expected ",measureTypes)
                self.osAbort()
            time.sleep(1)
        
        for index in range(0,measureTypes):
            valueMean= np.append(valueMean,float(strlist[5+8*index]))

        print("measurement mean:",valueMean,"counts=",cnt)
        return valueMean
            

    def setTimeBase_s(self, timeDiv_s, printEnabled=True):
        str=":TIMebase:SCALe "+f'{timeDiv_s}'
        if(printEnabled):print("MSO9254A::setTimeBase_s():",str)
        self.usb9254.write(str)
        timeScale=float(self.usb9254.query(":TIMebase:SCALe?"))
        if(not math.isclose(timeScale,timeDiv_s, abs_tol=timeScale*0.1)):
            print("MSO9254A::setTimeBase()= Warning: failed to set time scale, expected ",timeDiv_s," instead of", timeScale)
            self.osAbort()
        # print(self.usb9254.write(":TIMebase:SCALe 3E-6"))
    
    def setTimeBase_forFrequency_Hz(self, freq_Hz, periodCntPerDiv=1):
        timeDiv=1.0/freq_Hz
        timeDiv*=periodCntPerDiv
        self.setTimeBase_s(timeDiv)
        time.sleep(0.5)
        


##############################################################################################################################
# main
#
#
##############################################################################################################################
# if __name__ == "__main__":
#     dg1022=DG1022()
#     dg1022.openDevice()
    
#     frequency=100000
#     dg1022.setCh1_Sin_Hz_V_V(frequency,0.01,0.35)
#     dg1022.setCh1_On()
#     # dg1022.setChi_On(False)
#     dg1022.closeDevice()

#     mso9254=MSO9254A()
#     mso9254.openDevice()

#     mso9254.setTimeBase_forFrequency_Hz(frequency)
#     mso9254.fetchMeasureMean()

#     mso9254.closeDevice()

# if __name__ == "__main__":
#     dg1022=DG1022()
#     dg1022.openDevice()

#     # 设置信号源输出信号， 手动预设，不需要调整，只需要动态改变频率就行
#     # dg1022.setCh1_Sin_Hz_V_V(frequency,0.01,0.35)
#     # dg1022.setCh1_On()
    
    
#     frequency=100000
    
#     # 打开示波器接口
#     mso9254=MSO9254A()
#     mso9254.openDevice()

#     # 扫描信号源频率，使用示波器测量频率、输入幅度、输出幅度
    

#     wb = xlwt.Workbook()
#     ws = wb.add_sheet('OPAMP Frequency Responce')
#     ws.write(0, 0, 'Frequency settings [Hz]')
#     ws.write(0, 1, 'Frequency measured [Hz]')
#     ws.write(0, 2, 'Input Amp [V]')
#     ws.write(0, 3, 'Output Amp [V]')
#     ws.write(0, 4, 'Phase [degree]')
#     idx=0
#     for freqOrder in range(1,8):
#         for freqIndex in range(1,10):
#             frequency = freqIndex* pow(10,freqOrder)
#             if(frequency<25000000):
#                 dg1022.setCh1_Frequency_Hz(frequency)
#                 if(frequency<100):sCounts=20
#                 else:sCounts=100
#                 mso9254.setTimeBase_forFrequency_Hz(frequency)
#                 mList = mso9254.fetchMeasureMeanList(4,sCounts)
#                 freqMeasured = mList[0]
#                 phaseMeasured= mList[1]
#                 inputAmp     = mList[3]
#                 outputAmp    = mList[2]

#                 idx+=1
#                 ws.write(idx, 0, frequency)
#                 ws.write(idx, 1, freqMeasured)
#                 ws.write(idx, 2, inputAmp)
#                 ws.write(idx, 3, outputAmp)
#                 ws.write(idx, 4, phaseMeasured)

#     # wb.save('ROIC2_IBIAS_6uA_'+datetime.now().strftime('%Y%m%d%H%M%S')+'.xls')  #0.89V
#     # wb.save('ROIC2_IBIAS_10uA_'+datetime.now().strftime('%Y%m%d%H%M%S')+'.xls') #1.2V
#     # wb.save('ROIC2_IBIAS_14uA_'+datetime.now().strftime('%Y%m%d%H%M%S')+'.xls') #1.5V
#     # wb.save('ROIC2_IBIAS_18uA_'+datetime.now().strftime('%Y%m%d%H%M%S')+'.xls') #1.8V
#     # wb.save('ROIC2_IBIAS_22uA_'+datetime.now().strftime('%Y%m%d%H%M%S')+'.xls') #2.1V
#     wb.save('LMP7721_62k_Cf0_10pF10MPb_2V5_'+datetime.now().strftime('%Y%m%d%H%M%S')+'.xls') #2.4V


#     mso9254.closeDevice()
#     dg1022.closeDevice()
#     # 


# if __name__ == "__main__":

#     os.chdir(os.path.dirname(__file__))
#     print (os.path.abspath('.'))


#     txtDataArray=np.loadtxt("InCurrent.txt")
#     # print(currentArray)
#     lowVolt =-1.0
#     highVolt= 0.0

    
#     print(txtDataArray[:,1])
#     curColA=txtDataArray[:,1]
#     for i in range(len(curColA)):
#         if curColA[i]<0:
#             curColA[i]=0

#     ampl=max(curColA) - min(curColA)    
#     currentA = 16383-(curColA /ampl *16383.0)
#     print(currentA[6772])
#     print(len(currentA))

    
#     dg1022=DG1022()
#     dg1022.openDevice()

#     temp=currentA[6000:8048:2]
#     print(len(temp))
#     dg1022.set_voltage(lowVolt, highVolt)
#     dg1022.setVolatileMemData(10000,temp )
#     dg1022.setCh1_On()
#     dg1022.closeDevice()

class FastPlot(object): 
    

    def __init__(self, channelCnt=2):
        self.colorSet=['#FFD700','#20B2AA','#EE6AA7','#4169E1','green','red','cyan']
        #                gold LightSeaGreen  HotPink  RoyalBlue        
        self.chCnt = channelCnt
        self.fig = plt.figure(figsize=(18,9)) 
        self.set_chCnt(channelCnt) 

# rowId, colId, yData, 
    def plot(self,chID=0, **kwargs):
        # chID = kwargs.get('rowid')
        clearPlot=kwargs.get('append')
        xArray=kwargs.get('x')
        yArray=kwargs.get('y')
        if(len(yArray)>2048):
            dotStyle=","
        else:
            dotStyle="o"
        if(yArray is None):
            return
        if(xArray is None):
            xArray = np.arange(len(yArray))
        # if(chID is None):chID=0
        if(clearPlot is None):self.ax[chID].clear()
        self.ax[chID].grid(True)
        if(clearPlot is not None):self.ax[chID].plot(xArray, yArray,dotStyle,color=self.colorSet[chID])    
        else:         self.ax[chID].plot(xArray, yArray,dotStyle)    
        self.ax[chID].set_ylabel('  \n')    
        plt.tight_layout()
        self.show()
        


    def set_chCnt(self, channelCnt):
        self.chCnt = channelCnt
        self.ax = self.fig.subplots(channelCnt, 1) 
        self.fig.text(0, 0.5, '\nVoltage [V]\n', va='center', rotation='vertical')  
        plt.ion()    


    def plot_singleCh(self,chID=0, clearPlot=False, **kwargs):
        xArray=kwargs.get('x') 
        yArray=kwargs.get('y')  
        if(yArray is None):
            return
        if(xArray is None):
            xArray = np.arange(len(yArray))
        if(len(yArray)>2048):
            dotStyle=","
        else:
            dotStyle="o"
        if(chID<0 or chID>=self.chCnt):
            print("DG1022::plot_singleCh()= Error: Invalid chID=",chID)
            os.abort()
        if(clearPlot):self.ax[chID].clear()
        self.ax[chID].grid(True)
        if(clearPlot):self.ax[chID].plot(xArray, yArray,dotStyle,color=self.colorSet[chID])    
        else:         self.ax[chID].plot(xArray, yArray,dotStyle)    
        self.ax[chID].set_ylabel('  \n')    
        plt.tight_layout()
        plt.draw()
        plt.pause(0.1)
        # self.show()    
    
    def getSubplot(self,chID):
        return self.ax[chID]

    def set_ch_name(self, chID, name_str):
        self.ax[chID].set_title(name_str) 

    def set_time_unit_s(self):
        self.ax[self.chCnt-1].set_xlabel("time [s]\n")

    def set_time_unit_ms(self):
        self.ax[self.chCnt-1].set_xlabel("time [ms]\n")

    def set_time_unit_us(self):
        self.ax[self.chCnt-1].set_xlabel("time [µs]\n")

    def set_time_unit_ns(self):
        self.ax[self.chCnt-1].set_xlabel("time [ns]\n")

    def set_time_lim(self, min, max):
        for i in range(0, self.chCnt):
            self.ax[i].set_xlim(min, max)

    def show(self):
        plt.tight_layout()
        plt.ioff()        
        plt.show()
        plt.pause(0.2)

def saveCSV(self, fileName=None):
    self.csvData= self.xData[0]
    headTxt = "X0:" + self.xNames + "; " 
    fmtStr = '%f'
    for i in range(self.chCnt) :
        headTxt = headTxt + f'Y{i}:' + self.yNames[i] + " [V]; "
        self.csvData = np.column_stack((self.csvData, self.yData[i]))
        fmtStr +=' %f'
    headTxt= headTxt.replace('\n', ' ')
    print("ScopePlot::saveCSV(): header: # ", headTxt)
    print("ScopePlot::saveCSV(): data:", self.csvData)
    if(fileName==None):
        fileName = self.fileName.replace(".h5",".csv")
    np.savetxt(fileName,self.csvData ,fmt=fmtStr, delimiter="\n", header= headTxt)
    print("ScopePlot::saveCSV(): saved to file:", fileName)

if __name__ == "__main__":

    os.chdir(os.path.dirname(__file__))
    print (os.path.abspath('.'))


    txtDataArray=np.loadtxt("InCurrent.txt")
    # print(currentArray)
    lowVolt =-1.0
    highVolt= 0.0

    
    print(txtDataArray[:,1])
    curColA=txtDataArray[:,1]
    for i in range(len(curColA)):
        if curColA[i]<0:
            curColA[i]=0

    ampl=max(curColA) - min(curColA)    
    currentA = 16383-(curColA /ampl *16383.0)
    print(currentA[6772])
    print(len(currentA))

    
   

    temp=currentA[6000:8048:2]
    print(len(temp))
    print("temp array=",temp)

    b, a = signal.butter(8, 0.03, 'lowpass') 
    filtedData = signal.filtfilt(b, a, temp)

    for i in range(len(filtedData)):
        if (filtedData[i]>16383):
            filtedData[i]=16383

    state=0
    if(1==state):
        dg1022=DG1022()
        dg1022.openDevice()
        # dg1022.set_voltage(lowVolt, highVolt)
        dg1022.setVolatileMemData(10000,filtedData )
        dg1022.setCh1_On()
        dg1022.closeDevice()

    print("len of temp=",len(temp))
    print("len of filted=",len(filtedData))

    filtedData=temp.copy()
    
    filtedData-=np.max(filtedData)
    filtedData/=np.abs(np.min(filtedData))

    
    dataY= filtedData.copy()
    for i in range(100):
        dataY[i]= filtedData[924+i]
    for i in range(924):
        dataY[100+i]= filtedData[i]
    timeX= np.arange(0, 100000, 97.65625)
    print(len(timeX))

    dataYLong=np.arange(0,1000000, 97.65625)
    timeXLong=np.arange(0,1000000, 97.65625)
    dataYLong*=0
    for i in range(1024):
        dataYLong[7000+i]=dataY[i]

    csvData = np.column_stack((timeXLong, dataYLong))
    np.savetxt("PWLdata.csv",csvData ,fmt="%fn,%f,", delimiter="\n")

    fplot=FastPlot()
    fplot.plot_singleCh(y=temp)
    fplot.plot_singleCh(1,y=dataYLong)
    fplot.show()