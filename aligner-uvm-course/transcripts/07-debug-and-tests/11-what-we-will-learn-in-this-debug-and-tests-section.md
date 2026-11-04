# What we will learn in this "Debug and Tests" section

*Chapter: Debug and tests · source: pasted in chat*

Hi!
My name is Cristian Slav and in this introduction tutorial we are going to talk about what we will learn in this "Debug and Tests" section.
We managed to implement all the components part of our verification environment and now it's time to put them to work.
This means that we will have to start running regressions, so we will run a lot of random tests.
But some of those tests will fail and it is our job to debug and find the reason why those tests failed.
Some of the failures will prove to be RTL bugs, so the design team will have to fix the RTL code, but other failures will be environment bugs and it will be our job to fix the code in the environment.
But in order to identify why a test fail, we will have to debug all the tests which failed in our regressions.
Debugging the failures is a time-consuming task and for this reason learning some debug techniques will help us to reduce a little bit this time that we spend during debug.
So in this section we will learn some debug techniques which will help us reduce the time we spend to debug the failures in our regressions.
There are many debug techniques out there, some of them are well established and used by everybody, but you will also develop your own debug techniques throughout your career.
In this section of our training we will discuss three debug techniques.
In the first technique we will use UVM messages to clear up the log and only see the messages relevant for our failure.
Next, we will see how UVM transactions will help us clear up the waveforms and easily understand what is happening on the waveforms.
These two techniques are using features part of the UVM library, so these are well-known methods of debug in our industry.
But as I told you, throughout your career, most likely you will develop your own debug techniques to help you find the reason for a failure much faster.
This is also the case for me and I will share with you one way I'm using in order to easily track the source of some output from the RTL.
After that we will discuss how we can organize our tests in order to write them efficiently and to target particular features of the DUT.
Here we will update our register access test and also our random traffic test in order to really make use of the random feature of SystemVerilog language and maybe we will catch some real DUT bugs with our updated tests.
That's it for this short introduction in this "Debug and Tests" section.
In the next tutorial we will discuss how we can make use of the UVM message feature to help us with debug.
Thanks for watching and see you in the next tutorial.
Bye!
