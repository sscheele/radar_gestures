from matplotlib import pyplot as plt 
import numpy as np 
from matplotlib.animation import FuncAnimation  

import websocket
import _thread as thread
import time   

global freqs, highlight, time_offset
# freqs = [0.2, 0.5, 0.5, 1]
freqs = [1, 1]
highlight = -1
time_offset = 0

time_start = time.time()

fs = 50
sample_pd = 1000//fs

def init():  
    for c in circs:
        c.center = (1, 0)
    return circs
   
def animate(i):
    global freqs, highlight, time_offset
    for idx, c in enumerate(circs):
        update_term = 2*np.pi*freqs[idx]*(i-time_offset*fs)/fs
        if freqs[idx] < 0:
            update_term += np.pi
        c.center = (1.5*np.cos(update_term), 1.5*np.sin(update_term))
        if idx == highlight:
            c.set_color('g')
        else:
            c.set_color('b')
    return circs

# BEGIN WEBSOCKET CODE
def on_message(ws, message):
    global freqs, highlight, time_offset
    print(message)
    if message[0] == 'r':
        time_offset = time.time() - time_start
    if message[0] == 's':
        idx = int(message[1])
        rate = float(message[2:])
        freqs[idx] = rate
    if message[0] == 'h':
        highlight = int(message[1:])

def on_error(ws, error):
    print("Websocket error: ", error)

def on_close(ws):
    print("### Websocket closed ###")

def test_run(ws):
    def run():
        ws.send("h1")
        time.sleep(2)
        ws.send('r')
        time.sleep(2)
        ws.send('s0-0.8')
    thread.start_new_thread(run, ())

if __name__ == "__main__":
    # websocket.enableTrace(True)
    ws = websocket.WebSocketApp("ws://localhost:30000",
                              on_message = on_message,
                              on_error = on_error,
                              on_close = on_close)
    # ws.on_open = test_run          
    thread.start_new_thread(ws.run_forever, ())

    # marking the x-axis and y-axis 
    fig, axes = plt.subplots(1, 2, squeeze=True)
    axes = axes.ravel()
    # fig.set
    plt.subplots_adjust(left=0, bottom=0, right=1, top=1, wspace=0, hspace=0)
    for a in axes:
        a.set_xlim((-2, 2))
        a.set_ylim((-2, 2))
        a.xaxis.set_visible(False)
        a.yaxis.set_visible(False)
        a.set(adjustable='box', aspect='equal')

    circs = [plt.Circle((1, 0), 0.3, color='b') for _ in range(len(axes))]
    for i in range(len(axes)):
        axes[i].add_artist(circs[i])

    anim = FuncAnimation(fig, animate, init_func = init, interval = sample_pd, blit = True) 

plt.show()
