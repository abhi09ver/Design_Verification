# Draw some conclusions about our modeling and checking section

*Chapter: Modeling and checking · source: pasted in chat*

Hi!
My name is Cristian Slav and in this tutorial we are going to draw some conclusions about our modeling and checking section.
First of all, congratulations to you for completing this section!
You now know how to build all the components part of the verification environment.
This knowledge is very valuable and you should feel proud of yourself for learning this.
Let's quickly go through all the things that you learned in this section.
You learned how to model the behavior of a DUT.
You now know how to take the information from the model and check the outputs of a DUT.
You also saw the effects of synchronization issues in your model and you learned how to solve them.
We use process pointers and internal probing in order to solve our synchronization issues.
But there are other techniques for solving such synchronization issues.
For example, you might have a DUT which will allow you to isolate the sub-module which is introducing these synchronization issues.
A classic example for this would be an internal arbiter.
To solve this synchronization issue, you can extract the arbiter from the DUT and verify it separately.
Another technique for dealing with synchronization issues is to write directed tests for that functionality which is introducing those synchronization issues.
This would be also a good technique for the issue that we had with the interrupts.
We could have solved this synchronization issue by writing directed tests in which we verify separately the interrupts.
There are many other techniques for dealing with synchronization issues.
Throughout your career, you'll learn many such techniques for dealing with synchronization issues and it will be up to you to choose the best one for the device that you have to verify.
You also learn how to develop the functional coverage for the DUT.
We wrote the coverage for just one feature of the DUT, that split functionality, and you saw that this is quite a time-consuming task.
So writing the functional coverage for a DUT is quite a long process and this is something that you should definitely take into consideration when you are planning the verification of a DUT.
You also learned how to use virtual sequences to develop complex and reusable scenarios.
Remember that we developed that slow pace virtual sequence, and because that complex scenario is now wrapped in a virtual sequence, it's quite easy for us now to reuse that sequence throughout our tests.
Now our verification environment is complete and it's time for us to put it to work.
In the next section of our training we will discuss some debugging techniques which will make our lives a bit easier when we will deal with failing tests and we will also learn how to write and organize our tests.
That's it for this tutorial.
I hope everything was clear for you throughout this section.
Thank you for watching and see you in the next tutorial.
Bye!
