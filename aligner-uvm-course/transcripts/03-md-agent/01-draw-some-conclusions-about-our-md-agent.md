# Draw some conclusions about our MD agent

*Chapter: MD agent · source: attached*

Hi!
My name is Cristian Slav and in this tutorial we are going to draw some conclusions about our MD agent.
First of all, congratulations to you for completing the MD agent.
You learned a lot while building this MD agent and let's recap a little bit all the new information that you learned during this section.
You learn how to identify protocol specific rules from the DUT specification.
Remember that for the MD protocol, we don't have a document listing all the rules of this MD protocol.
We actually extracted those rules from the Aligner specification, and this is a common thing that you will encounter in your professional life.
And not only that, you learn how to identify the rules, but you also applied those rules as checks and coverage in the MD agent.
You now know how to build an agent with both master and slave aspects.
Our MD agent is now instantiated for the RX and TX interface, master and slave.
And one very important thing is that we applied inheritance in order to develop the common parts from this master and slave aspects.
You also learn how to build a parameterized agent.
And you saw that this technique is quite prone to error.
You have to be very careful that you pass that parameter correctly from one class to another, but if you are careful when you are doing the coding then you'll obtain an agent which will be much more flexible to be used in different projects.
One other thing that you learn is how to write checks in that constant context.
Remember that in the MD interface we added those two checks for the data width in the interface, and those checks are triggered immediately when the interface gets instantiated.
And finally, you saw how it is to run the same SV code but on different simulators.
In such a scenario, you would assume that the same SV code will run exactly the same regardless of the simulator.
But you saw that there are subtle differences between the simulators.
Some syntax is supported by some and not supported by others.
And when you are developing a commercial SV package, you need to be aware of this.
If we look at the image of our verification environment, we actually managed to implement all three agents, and from this point forward we can work with transactions rather than signals on the interface.
So from each of those agents, when we want to send some information, we actually work with the UVM sequence items sent to the driver, or when we want to collect that information, we simply look at the monitor inside each of those agents and we work with the class sent to us by the monitor, so we are no longer required to work with each individual signal part of the APB or the MD protocol.
But in the next section of our training, we will spend just a little bit of time with these agents because we will learn an advanced technique of building such an UVM agent.
And this will allow you, the next time when you have to build an agent, to be quite fast in developing that agent that you need.
And one last thing before closing this tutorial, you see that we have here quite a bunch of files that we created when we developed the MD agent.
And this is fine if you are in a real project, but here on EDA playground, adding those files will make our window smaller and smaller every time.
So just like we did for the APB package, we will also do the same thing for the MD package.
We will copy the content of all these files under our MD package.
And because this is not something that you should do in a real project, and we do this only to optimize the space in the EDA Playground, you can skip this part and just let me move all the content of those files in our cfs_md_pkg file.
So just remember that starting with the next tutorial, you will find all the code part of the MD agent in one file here.
That's it.
Our EDA Playground project looks much more clean now.
All the files were copy pasted in this cfs_md_pkg.
And even though this is not something that you need to do in a real project, in a real project, again, you have to keep all those classes in separate files.
By doing this, we can see how many lines of code we had to write for our MD agent.
So we had to write around 1276 lines of code and we can easily compare this with the APB package for which we had to write around 940.
So with just 350 extra lines of code, let's say more or less, we actually developed an agent with two aspects, a master aspect and a slave aspect.
So developing such a big agent is quite an accomplishment.
So congratulations again to you for completing the MD agent.
That's it for this tutorial.
Thanks for watching.
I hope everything was clear for you throughout this MD Agent and see you in the next tutorial.
Bye!
