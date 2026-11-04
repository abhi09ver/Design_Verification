# Draw some conclusions about our UVM extension package

*Chapter: UVM extension library · source: attached*

Hi, my name is Cristian Slav and in this tutorial we are going to draw some conclusions about our UVM extension package.
First of all, congratulations to you for completing this section of the training.
Let's look to see exactly what we accomplished in this section.
Initially, we started from our APB and MD packages which are using the UVM package in order to implement the agents for the two protocols.
But because there was a lot of code which was repeated in these two agents, we created an intermediate package called UVM extension package, with the purpose of moving inside here all the repetitive code from the APB and MD packages.
And now it's time to see if our code in those two packages actually got shorter.
I've opened here two projects.
First is the "UVM Extension Agent Configuration - Practice", which is the starting project in this current section regarding the UVM extension package.
And then I have this other project "UVM Extension Agent - Solution" in which we finished implementing the entire UVM extension package.
So let's see the difference in number of lines between these two projects for our two packages.
First the APB package before we implemented the UVM extension package, had 940 lines, and after we implemented the UVM extension package, it got down to 617 lines. it got down to 617 lines.
So this means that we actually reduced this package by 323 lines. this package by 323 lines.
So let's see now how we stay with our MD package.
So before we implemented the UVM extension package, this one had 1278 lines of code and after we implemented the UVM extension package it was reduced to 953 lines of code.
This means that we reduced 325 lines.
And let's see those figures also in our PowerPoint presentation.
So the APB was reduced by 323 lines of code.
This means that we reduce it by 34%.
And for the MD package we reduce it by 325 lines of code. the MD package we reduce it by 325 lines of code.
And in percentage this means 25%.
And in percentage this means 25%.
So this is quite a big reduction in the code of our two packages.
Probably this 34% is the biggest value that we will get as the APB is quite simple.
And because the MD package was longer in number of lines of code, we reduce it by 25%.
But the absolute number of lines is more or less the same between these two.
So it really paid off to implement this UVM extension package as the next time you will have to implement an agent, if you use this package, then you will not have to write those 325 lines of extra code.
Let's see what should be the future of this UVM extension package.
My first recommendation to you is to add in this package any repetitive code that you will encounter in your career which you can reuse using the inheritance part of the object oriented programming technique.
I'm pretty sure that at some point you will realize that you are writing the same class over and over again in all your projects, so that would be a good hint that you can actually place that class in this UVM extension package and in your future projects you can reuse it from there.
But besides classes which we can define in the UVM extension package and then reuse them by means of inheritance, we can also have repetitive code which cannot be used in such a manner.
And that repetitive code we actually have to write.
And that is a good indication that we can actually use some file generation technique or some code generation technique.
And let me show you an example of how we can use this in our UVM extension package.
So currently we have our UVM extension package with our two packages for the APB and for the MD.
But actually the structure of the files and classes inside these packages can be reused for other protocols, not just these ones.
So what we can do is to create some templates out of these packages.
For example we can create template #0 out of our APB package and this template #0 will contain the files and classes for an agent which is implemented only for one aspect, just like we did for our APB we implemented only as a master.
So we can obtain this template #0 by removing from our APB package anything related to APB.
So for example the collect_transaction() or drive_transaction() will be empty and also the monitor item or drive item will not have any fields which are part of the APB protocol.
And the same thing we can do with our MD package.
We can create a template #1 and this template #1 will contain the files and classes of an agent which we want to develop with two aspects, master and slave.
And you'll see that once you get more experience as a verification engineer that you will easily identify more architectures with which you can build an agent.
So you can add more templates to this template pool.
But once you have this template pool, you can actually create a simple Python script in which you will generate an agent based on some template from this pool.
So for example you can call the script with some arguments like this one in which you specify for example the company to be Infineon or the protocol to be AHB and the template to be #0.
And this will generate the files and classes for an agent called ifx_ahb which will be generated from template #0.
And once you have these files, you can add only the code specific to the AHB protocol.
For example, you can add the fields in the monitor item or the fields in the driving item, you can add the code to collect the transaction or to drive a transaction and so on.
But you will not have to define the files and classes as we did for the APB and for the MD packages.
And it will be the same thing if you want to generate an agent from template #1.
Let's say that you are working for Apple and they ask you to build an agent for the AXI protocol.
And then you simply call this script using the company the Apple symbol and then for the protocol AXI, and you say that you want to generate the agent using template #1, because let's say that this agent should support also the master and slave aspects and this will generate all the files and classes for such an agent.
So this is one example in which you can generate code from the UVM extension package.
But you will see that there are other scenarios in which this can be applied.
Not only for the agents, there can be code which you can generate for the register layer or even for the environment.
But all this you will discover on your own once you gain more and more experience.
And one last thing, as a general idea, my recommendation to you is to use the UVM extension package as a compendium for your experience as a verification engineer.
You should put here anything that you realize at some point that you have to code over and over again.
Just to not reinvent the wheel every time, put it here and in your next project you simply include this package and use that code from here directly.
So let's recap what we learn and discuss in this section.
We learn how to build generic classes for an UVM agent and how to use these generic classes to build an UVM agent.
And, as advantages, there are three main advantages: less repetitive code, we reduce the probability of introducing some errors in our code, and finally, the development time is faster because we have to write less code obviously.
And finally we discuss what should be the future of this UVM extension package.
And before we close this tutorial, there is one more thing to do.
Just like we did for the APB and for the MD packages, in order to reduce the number of files which appear here in the EDA Playground project, I will move all the content of these files part of the UVM extension package inside this file, inside this uvm_ext_pkg.
And, as I told you before, this is not something that you will have to do in a real project.
In a real project you will have to keep all the classes in separate files.
But in our case, in the EDA Playground, just to maximize the size of this coding window, I'm going to move all those files here.
You don't have to do this on your own, just be aware that in the next tutorial you'll find all the classes of the UVM extension package in this file here.
That's it for this tutorial.
I hope everything was clear for you throughout this section.
Thanks for watching and see you in the next tutorial.
Bye!
